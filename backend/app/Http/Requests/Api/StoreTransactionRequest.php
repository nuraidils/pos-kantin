<?php

namespace App\Http\Requests\Api;

use App\Enums\PaymentMethod;
use Illuminate\Foundation\Http\FormRequest;
use Illuminate\Validation\Rule;
use Illuminate\Validation\Validator;

/**
 * Validasi bentuk dan konsistensi aritmetika payload (AGENTS.md §16).
 * Aturan stok TIDAK di sini: stok hanya boleh diputuskan di dalam database
 * transaction (TransactionService), bukan dari pembacaan awal yang bisa basi.
 */
class StoreTransactionRequest extends FormRequest
{
    public function authorize(): bool
    {
        return true;
    }

    public function rules(): array
    {
        return [
            'local_uuid' => ['required', 'uuid'],
            // Dikirim perangkat. Bila kosong, server membuat sendiri.
            'invoice_number' => ['nullable', 'string', 'max:40', 'regex:/^[A-Za-z0-9\-]+$/'],
            'payment_method' => ['required', Rule::enum(PaymentMethod::class)],
            'total_amount' => ['required', 'integer', 'min:1', 'max:4000000000'],
            // Waktu penjualan menurut perangkat; toleransi selisih jam sehari.
            'created_at' => ['required', 'date', 'before_or_equal:'.now()->addDay()->toIso8601String()],
            'items' => ['required', 'array', 'min:1', 'max:100'],
            'items.*.product_id' => ['required', 'integer', 'distinct', 'exists:products,id'],
            'items.*.quantity' => ['required', 'integer', 'min:1', 'max:9999'],
            'items.*.price' => ['required', 'integer', 'min:0', 'max:100000000'],
            'items.*.subtotal' => ['required', 'integer', 'min:0', 'max:4000000000'],
        ];
    }

    public function messages(): array
    {
        return [
            'local_uuid.required' => 'local_uuid wajib diisi.',
            'local_uuid.uuid' => 'local_uuid harus berupa UUID.',
            'invoice_number.regex' => 'Format nomor invoice tidak valid.',
            'payment_method.required' => 'Metode pembayaran wajib diisi.',
            'payment_method.enum' => 'Metode pembayaran tidak valid.',
            'total_amount.required' => 'Total pembayaran wajib diisi.',
            'total_amount.integer' => 'Total pembayaran tidak valid.',
            'total_amount.min' => 'Total pembayaran tidak valid.',
            'created_at.required' => 'Waktu transaksi wajib diisi.',
            'created_at.date' => 'Waktu transaksi tidak valid.',
            'created_at.before_or_equal' => 'Waktu transaksi tidak boleh di masa depan.',
            'items.required' => 'Transaksi harus memiliki minimal satu produk.',
            'items.min' => 'Transaksi harus memiliki minimal satu produk.',
            'items.max' => 'Jumlah produk dalam satu transaksi terlalu banyak.',
            'items.*.product_id.exists' => 'Produk tidak ditemukan.',
            'items.*.product_id.distinct' => 'Produk yang sama tidak boleh muncul dua kali.',
            'items.*.quantity.min' => 'Jumlah produk tidak valid.',
            'items.*.quantity.integer' => 'Jumlah produk tidak valid.',
            'items.*.quantity.max' => 'Jumlah produk tidak valid.',
        ];
    }

    /**
     * Server tidak mempercayai total dari klien begitu saja (AGENTS.md §16):
     * subtotal harus = harga x jumlah, dan total harus = jumlah semua subtotal.
     *
     * @return list<callable(Validator): void>
     */
    public function after(): array
    {
        return [
            function (Validator $validator): void {
                if ($validator->errors()->isNotEmpty()) {
                    return;
                }

                $sum = 0;
                foreach ($this->input('items') as $index => $item) {
                    // Aturan 'integer' juga meloloskan string numerik ("20000"), jadi di-cast dulu.
                    $expected = (int) $item['price'] * (int) $item['quantity'];

                    if ((int) $item['subtotal'] !== $expected) {
                        $validator->errors()->add(
                            "items.$index.subtotal",
                            'Subtotal tidak sesuai dengan harga dan jumlah.'
                        );
                    }

                    $sum += $expected;
                }

                if ($this->integer('total_amount') !== $sum) {
                    $validator->errors()->add(
                        'total_amount',
                        'Total pembayaran tidak sesuai dengan jumlah subtotal.'
                    );
                }
            },
        ];
    }
}
