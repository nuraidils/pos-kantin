<?php

namespace App\Services;

use App\Enums\SyncStatus;
use App\Exceptions\InsufficientStockException;
use App\Models\Product;
use App\Models\Transaction;
use App\Models\User;
use Illuminate\Database\UniqueConstraintViolationException;
use Illuminate\Support\Carbon;
use Illuminate\Support\Facades\DB;
use Illuminate\Support\Str;
use Illuminate\Validation\ValidationException;

class TransactionService
{
    /** Percobaan ulang bila dua request berbeda berebut nomor invoice yang sama. */
    private const MAX_ATTEMPTS = 3;

    /**
     * Menerima satu transaksi dari perangkat secara idempoten (AGENTS.md §10, §13.3).
     *
     * `local_uuid` yang sama dua kali tidak membuat transaksi kedua dan tidak
     * mengurangi stok lagi: hasil yang sudah ada dikembalikan apa adanya.
     *
     * @param  array{
     *     local_uuid: string,
     *     invoice_number?: ?string,
     *     payment_method: string,
     *     created_at: string,
     *     items: list<array{product_id: int, quantity: int, price: int}>
     * }  $data
     * @return array{transaction: Transaction, created: bool}
     *
     * @throws InsufficientStockException  stok server kurang; tidak ada yang tersimpan
     * @throws ValidationException         local_uuid sudah dipakai pengguna lain
     */
    public function store(User $user, array $data): array
    {
        for ($attempt = 1; ; $attempt++) {
            try {
                return DB::transaction(fn () => $this->storeWithinTransaction($user, $data));
            } catch (UniqueConstraintViolationException $e) {
                // Dua request berebut kunci unik. Bila itu local_uuid yang sama,
                // pemenangnya sudah commit: kembalikan hasilnya (idempoten).
                $existing = $this->findByLocalUuid($data['local_uuid']);
                if ($existing !== null) {
                    return ['transaction' => $this->ownedBy($existing, $user), 'created' => false];
                }

                // Selain itu: tabrakan invoice_number. Coba lagi; nomor akan diberi akhiran.
                if ($attempt >= self::MAX_ATTEMPTS) {
                    throw $e;
                }
            }
        }
    }

    /**
     * @return array{transaction: Transaction, created: bool}
     */
    private function storeWithinTransaction(User $user, array $data): array
    {
        // Aturan 'integer' di request juga meloloskan string numerik; seragamkan jadi int.
        $items = collect($data['items'])->map(fn (array $item) => [
            'product_id' => (int) $item['product_id'],
            'quantity' => (int) $item['quantity'],
            'price' => (int) $item['price'],
        ]);

        // 1) Kunci baris produk, urut id agar dua request tidak saling menunggu
        //    melingkar (deadlock). withTrashed: produk yang dihapus/dinonaktifkan
        //    owner setelah sinkronisasi terakhir tetap punya stok yang harus dijaga.
        $products = Product::query()
            ->withTrashed()
            ->whereIn('id', $items->pluck('product_id'))
            ->orderBy('id')
            ->lockForUpdate()
            ->get()
            ->keyBy('id');

        // 2) Cek idempotensi SETELAH kunci produk didapat. Permintaan kembar yang
        //    menunggu kunci akan melihat hasil commit pemenangnya di sini, jadi
        //    tidak salah dijawab "stok kurang" karena stok sudah berkurang oleh dirinya sendiri.
        $existing = Transaction::query()
            ->where('local_uuid', $data['local_uuid'])
            ->lockForUpdate()
            ->first();

        if ($existing !== null) {
            return ['transaction' => $this->ownedBy($existing, $user), 'created' => false];
        }

        // 3) Stok server adalah otoritas (AGENTS.md §13.1). Kumpulkan semua
        //    kekurangan sekaligus supaya perangkat tahu seluruh masalahnya.
        $shortages = [];
        foreach ($items as $item) {
            $product = $products[$item['product_id']];

            if ($product->stock < $item['quantity']) {
                $shortages[] = [
                    'product_id' => $product->id,
                    'product_name' => $product->name,
                    'requested' => $item['quantity'],
                    'available' => $product->stock,
                ];
            }
        }

        if ($shortages !== []) {
            throw new InsufficientStockException($shortages);
        }

        // 4) Tulis transaksi + item (snapshot) dan kurangi stok. Total dihitung
        //    ulang dari item, bukan diambil dari klien.
        $total = $items->sum(fn (array $item) => $item['price'] * $item['quantity']);

        $transaction = Transaction::create([
            'local_uuid' => $data['local_uuid'],
            'user_id' => $user->id,
            'invoice_number' => $this->uniqueInvoiceNumber($data['invoice_number'] ?? null, $data['local_uuid'], $data['created_at']),
            'total_amount' => $total,
            'payment_method' => $data['payment_method'],
            'sync_status' => SyncStatus::Synced,
            'created_at' => Carbon::parse($data['created_at']),
            'synced_at' => now(),
        ]);

        foreach ($items as $item) {
            $product = $products[$item['product_id']];

            $transaction->items()->create([
                'product_id' => $product->id,
                'product_name' => $product->name,
                'quantity' => $item['quantity'],
                'price' => $item['price'],
                'subtotal' => $item['price'] * $item['quantity'],
            ]);

            // Lewat Eloquent (bukan DB::table) agar updated_at ikut berubah dan
            // sinkronisasi inkremental katalog mengirim stok baru ke perangkat.
            $product->decrement('stock', $item['quantity']);
        }

        return ['transaction' => $transaction->load('items'), 'created' => true];
    }

    /**
     * invoice_number UNIQUE di server, sedangkan dua perangkat bisa menghasilkan
     * nomor yang sama. Server tidak boleh menolak transaksi yang sah, jadi nomor
     * yang bertabrakan diberi akhiran -2, -3, ... (AGENTS.md §21).
     */
    private function uniqueInvoiceNumber(?string $requested, string $localUuid, string $createdAt): string
    {
        $base = $requested ?: sprintf(
            'INV-%s-%s',
            Carbon::parse($createdAt)->format('Ymd'),
            Str::upper(substr(str_replace('-', '', $localUuid), 0, 6)),
        );

        $candidate = $base;
        for ($n = 2; Transaction::query()->where('invoice_number', $candidate)->exists(); $n++) {
            $suffix = '-'.$n;
            $candidate = substr($base, 0, 40 - strlen($suffix)).$suffix;
        }

        return $candidate;
    }

    private function findByLocalUuid(string $localUuid): ?Transaction
    {
        return Transaction::query()->with('items')->where('local_uuid', $localUuid)->first();
    }

    /**
     * Hasil lama hanya boleh dikembalikan ke pemiliknya.
     *
     * @throws ValidationException
     */
    private function ownedBy(Transaction $transaction, User $user): Transaction
    {
        if ($transaction->user_id !== $user->id) {
            throw ValidationException::withMessages([
                'local_uuid' => 'local_uuid sudah dipakai oleh transaksi lain.',
            ]);
        }

        return $transaction->loadMissing('items');
    }
}
