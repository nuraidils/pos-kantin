import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:kasir_kantin/core/database/app_database.dart';
import 'package:kasir_kantin/core/network/api_client.dart';
import 'package:kasir_kantin/features/sync/presentation/bloc/sync_bloc.dart';
import 'package:kasir_kantin/features/transactions/data/transaction_local_data_source.dart';
import 'package:kasir_kantin/features/transactions/data/transaction_remote_data_source.dart';
import 'package:kasir_kantin/features/transactions/data/transaction_repository_impl.dart';
import 'package:kasir_kantin/features/transactions/domain/checkout_line.dart';
import 'package:kasir_kantin/features/transactions/domain/payment_method.dart';
import 'package:kasir_kantin/features/transactions/domain/sync_status.dart';
import 'package:path/path.dart' as p;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

/// Alur lengkap sisi perangkat (AGENTS.md §27, "Persistence"): SQLite berkas
/// sungguhan + repository + SyncBloc sungguhan, berhadapan dengan server palsu
/// yang berperilaku seperti Laravel (idempoten lewat local_uuid, 409 saat stok
/// kurang). Tiap lapisan sudah punya tesnya sendiri; tes ini memastikan
/// rangkaiannya benar:
///
///   transaksi offline -> aplikasi ditutup dan dibuka -> internet kembali
///   -> sinkron -> server berisi tepat satu transaksi per penjualan.

/// Server palsu. Seluruh keadaannya bisa diatur dari tes.
class FakeServer {
  FakeServer(this.stock);

  /// Stok server per product_id.
  final Map<int, int> stock;

  /// Transaksi yang diterima, per local_uuid.
  final Map<String, Map<String, dynamic>> stored = {};

  bool online = true;

  /// Server menerima transaksi, tetapi balasannya hilang di jalan.
  bool dropNextResponse = false;

  /// Jumlah permintaan yang benar-benar sampai ke server.
  int posts = 0;

  http.Response _json(int status, Map<String, dynamic> body) => http.Response(
    jsonEncode(body),
    status,
    headers: {'content-type': 'application/json'},
  );

  Future<http.Response> handle(http.Request request) async {
    if (!online) throw const SocketException('tidak ada internet');
    posts++;

    final body = jsonDecode(request.body) as Map<String, dynamic>;
    final uuid = body['local_uuid'] as String;
    final items = (body['items'] as List).cast<Map<String, dynamic>>();

    // Idempoten: UUID yang sama dijawab dengan hasil lama, tanpa efek apa pun.
    if (stored.containsKey(uuid)) {
      return _json(200, {
        'data': {
          'id': stored.keys.toList().indexOf(uuid) + 1,
          'invoice_number': body['invoice_number'],
          'synced_at': '2026-10-17T07:00:00Z',
        },
        'meta': {'duplicate': true},
      });
    }

    final shortages = [
      for (final item in items)
        if ((stock[item['product_id']] ?? 0) < (item['quantity'] as int))
          {
            'product_name': 'Kopi Susu',
            'requested': item['quantity'],
            'available': stock[item['product_id']] ?? 0,
          },
    ];
    if (shortages.isNotEmpty) {
      return _json(409, {
        'message': 'Stok tidak mencukupi.',
        'code': 'insufficient_stock',
        'shortages': shortages,
      });
    }

    for (final item in items) {
      stock[item['product_id'] as int] =
          stock[item['product_id']]! - (item['quantity'] as int);
    }
    stored[uuid] = body;

    final response = _json(201, {
      'data': {
        'id': stored.length,
        'invoice_number': body['invoice_number'],
        'synced_at': '2026-10-17T07:00:00Z',
      },
      'meta': {'duplicate': false},
    });
    if (dropNextResponse) {
      dropNextResponse = false;
      throw const SocketException('koneksi terputus sebelum balasan tiba');
    }
    return response;
  }
}

/// Satu "kali aplikasi dibuka": database, repository, dan SyncBloc.
class AppInstance {
  AppInstance._(this.db, this.repository, this.bloc);

  final AppDatabase db;
  final TransactionRepositoryImpl repository;
  final SyncBloc bloc;

  static int _minute = 0;

  static Future<AppInstance> open(String path, FakeServer server) async {
    final db = await AppDatabase.open(path: path);
    final client = ApiClient(
      baseUrl: 'http://test/api',
      tokenProvider: () async => 'token',
      httpClient: MockClient(server.handle),
    );
    final repository = TransactionRepositoryImpl(
      local: TransactionLocalDataSource(
        db,
        // Waktu penjualan berurutan agar urutan kirim pasti.
        clock: () => DateTime(2026, 10, 17, 9, _minute++),
      ),
      remote: TransactionRemoteDataSource(client),
    );
    return AppInstance._(db, repository, SyncBloc(repository: repository));
  }

  /// Aplikasi ditutup.
  Future<void> close() async {
    await bloc.close();
    await db.close();
  }

  Future<int> stockOf(int productId) async {
    final rows = await db.db.query(
      'products',
      columns: ['stock'],
      where: 'id = ?',
      whereArgs: [productId],
    );
    return rows.first['stock'] as int;
  }

  Future<void> seedProduct(int id, String name, int price, int stock) {
    return db.db.insert('products', {
      'id': id,
      'category_id': 1,
      'name': name,
      'price': price,
      'stock': stock,
      'is_active': 1,
      'updated_at': '2026-10-17T00:00:00+00:00',
    });
  }

  Future<String> sell(List<(int, int)> lines, {PaymentMethod? method}) async {
    final tx = await repository.createLocalTransaction(
      lines: [
        for (final (id, quantity) in lines)
          CheckoutLine(
            productId: id,
            name: 'x',
            quantity: quantity,
            expectedPrice: id == 1 ? 10000 : 8000,
          ),
      ],
      paymentMethod: method ?? PaymentMethod.cash,
    );
    return tx.localUuid;
  }

  Future<SyncStatus> statusOf(String uuid) async =>
      (await repository.getTransaction(uuid))!.syncStatus;
}

/// Menunggu kondisi terpenuhi. Memakai waktu nyata karena SQLite berkas
/// bekerja di luar antrean microtask Dart.
Future<void> waitUntil(bool Function() condition) async {
  for (var i = 0; i < 500; i++) {
    if (condition()) return;
    await Future<void>.delayed(const Duration(milliseconds: 10));
  }
  fail('Kondisi tidak tercapai dalam 5 detik.');
}

void main() {
  sqfliteFfiInit();
  databaseFactory = databaseFactoryFfi;

  late Directory dir;
  late String dbPath;

  setUp(() async {
    dir = await Directory.systemTemp.createTemp('kasir_kantin_it_');
    dbPath = p.join(dir.path, 'kasir_kantin.db');
  });

  tearDown(() async {
    // Di Windows berkas yang masih terbuka tidak bisa dihapus; folder
    // sementara ini boleh tertinggal, jadi galatnya diabaikan.
    try {
      if (dir.existsSync()) await dir.delete(recursive: true);
    } on FileSystemException {
      // Diabaikan.
    }
  });

  test('offline -> tutup dan buka aplikasi -> online -> sinkron: '
      'server berisi tepat satu transaksi per penjualan', () async {
    final server = FakeServer({1: 10, 2: 5})..online = false;
    var app = await AppInstance.open(dbPath, server);
    addTearDown(() => app.close());
    await app.seedProduct(1, 'Kopi Susu', 10000, 10);
    await app.seedProduct(2, 'Roti', 8000, 5);

    // 1. Dua penjualan saat internet mati. Kasir tidak menunggu apa pun.
    final first = await app.sell([(1, 2)]);
    final second = await app.sell([(2, 1), (1, 1)], method: PaymentMethod.qris);
    expect(await app.stockOf(1), 7);
    expect(await app.stockOf(2), 4);

    // 2. Percobaan kirim gagal; tidak ada yang hilang dan server kosong.
    app.bloc.add(const SyncStarted());
    await waitUntil(
      () => app.bloc.state.lastRunFailed && !app.bloc.state.isSyncing,
    );
    expect(server.stored, isEmpty);
    expect(await app.statusOf(first), SyncStatus.failed);
    expect(await app.statusOf(second), SyncStatus.pending);
    expect(await app.repository.countUnsyncedTransactions(), 2);

    // 3. Aplikasi ditutup lalu dibuka lagi: semuanya masih ada.
    await app.close();
    app = await AppInstance.open(dbPath, server);
    final all = await app.repository.getAllTransactions();
    expect(all.map((t) => t.localUuid), containsAll([first, second]));
    expect(all, hasLength(2));
    expect(await app.stockOf(1), 7);
    expect(await app.stockOf(2), 4);

    // 4. Internet kembali: keduanya sinkron, masing-masing sekali.
    server.online = true;
    app.bloc.add(const SyncStarted());
    await waitUntil(() => app.bloc.state.changeRevision > 0);

    expect(server.stored.keys, unorderedEquals([first, second]));
    expect(server.posts, 2);
    expect(await app.statusOf(first), SyncStatus.synced);
    expect(await app.statusOf(second), SyncStatus.synced);
    expect(await app.repository.countUnsyncedTransactions(), 0);
    // Stok server dan proyeksi stok perangkat sepakat.
    expect(server.stock, {1: 7, 2: 4});
    expect(await app.stockOf(1), 7);
    expect(await app.stockOf(2), 4);

    // 5. Pemicu berikutnya tidak mengirim apa pun lagi.
    app.bloc.add(const SyncRequested());
    await Future<void>.delayed(const Duration(milliseconds: 300));
    expect(server.posts, 2);
    expect(server.stored, hasLength(2));
  });

  test('balasan server hilang -> kirim ulang: tetap satu transaksi dan '
      'stok server berkurang sekali', () async {
    final server = FakeServer({1: 10})..dropNextResponse = true;
    final app = await AppInstance.open(dbPath, server);
    addTearDown(app.close);
    await app.seedProduct(1, 'Kopi Susu', 10000, 10);

    final uuid = await app.sell([(1, 2)]);

    // Server sudah menerima, tetapi perangkat mengira gagal.
    app.bloc.add(const SyncRequested());
    await waitUntil(
      () => app.bloc.state.lastRunFailed && !app.bloc.state.isSyncing,
    );
    expect(server.stored, hasLength(1));
    expect(await app.statusOf(uuid), SyncStatus.failed);

    // Pengiriman ulang dijawab "duplikat" dan dianggap berhasil.
    app.bloc.add(const SyncRequested());
    await waitUntil(() => app.bloc.state.changeRevision > 0);

    expect(await app.statusOf(uuid), SyncStatus.synced);
    expect(server.posts, 2);
    expect(server.stored, hasLength(1));
    expect(server.stock[1], 8, reason: 'Stok server hanya berkurang sekali.');
  });

  test('stok server kurang -> konflik tersimpan di perangkat -> '
      'stok ditambah -> Kirim Ulang diterima', () async {
    final server = FakeServer({1: 1}); // server hanya punya 1
    final app = await AppInstance.open(dbPath, server);
    addTearDown(app.close);
    await app.seedProduct(1, 'Kopi Susu', 10000, 10); // perangkat mengira 10

    final uuid = await app.sell([(1, 3)]);

    app.bloc.add(const SyncRequested());
    await waitUntil(() => app.bloc.state.changeRevision > 0);

    // Ditolak utuh, tetapi tidak hilang dari perangkat (Rule 6).
    expect(server.stored, isEmpty);
    expect(await app.statusOf(uuid), SyncStatus.conflict);
    expect(app.bloc.state.conflictCount, 1);
    final conflict = (await app.repository.getConflictTransactions()).single;
    expect(conflict.syncMessage, contains('diminta 3, tersedia 1'));
    expect(await app.stockOf(1), 10, reason: 'Stok lokal dikembalikan.');

    // Konflik tidak dikirim ulang diam-diam.
    app.bloc.add(const SyncRequested());
    await Future<void>.delayed(const Duration(milliseconds: 300));
    expect(server.posts, 1);

    // Owner menambah stok server; kasir menekan Kirim Ulang.
    server.stock[1] = 10;
    expect(await app.repository.retryConflict(uuid), isTrue);
    final revision = app.bloc.state.changeRevision;
    app.bloc.add(const SyncRequested());
    await waitUntil(() => app.bloc.state.changeRevision > revision);

    expect(await app.statusOf(uuid), SyncStatus.synced);
    expect(server.stored.keys, [uuid]);
    expect(server.stock[1], 7);
    expect(await app.stockOf(1), 7);
    expect(app.bloc.state.conflictCount, 0);
  });
}
