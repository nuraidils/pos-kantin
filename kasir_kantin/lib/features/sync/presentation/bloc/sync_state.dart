part of 'sync_bloc.dart';

class SyncState extends Equatable {
  const SyncState({
    this.isSyncing = false,
    this.unsyncedCount = 0,
    this.conflictCount = 0,
    this.lastRunFailed = false,
    this.changeRevision = 0,
  });

  /// Ada transaksi yang sedang dikirim.
  final bool isSyncing;

  /// Transaksi yang belum diterima server dan masih akan dicoba
  /// (`pending`, `syncing`, `failed`).
  final int unsyncedCount;

  /// Transaksi `conflict`: tidak dikirim ulang dan tidak boleh hilang
  /// diam-diam (AGENTS.md §13.4). Rinciannya menyusul di Tahap 14.
  final int conflictCount;

  /// Putaran terakhir berhenti karena transaksi gagal dikirim (jaringan,
  /// server, atau akses). Sisanya akan dicoba lagi otomatis.
  final bool lastRunFailed;

  /// Naik setiap putaran yang mengubah data lokal (ada yang `synced` atau
  /// `conflict`). AppShell memakainya untuk membaca ulang dan menarik katalog.
  final int changeRevision;

  SyncState copyWith({
    bool? isSyncing,
    int? unsyncedCount,
    int? conflictCount,
    bool? lastRunFailed,
    int? changeRevision,
  }) {
    return SyncState(
      isSyncing: isSyncing ?? this.isSyncing,
      unsyncedCount: unsyncedCount ?? this.unsyncedCount,
      conflictCount: conflictCount ?? this.conflictCount,
      lastRunFailed: lastRunFailed ?? this.lastRunFailed,
      changeRevision: changeRevision ?? this.changeRevision,
    );
  }

  @override
  List<Object?> get props => [
    isSyncing,
    unsyncedCount,
    conflictCount,
    lastRunFailed,
    changeRevision,
  ];
}
