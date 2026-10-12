import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../bloc/sync_bloc.dart';

/// Pemicu sinkronisasi berkala dan saat aplikasi dibuka kembali. Hanya
/// mengirim event ke [SyncBloc]; semua keputusan ada di BLoC (Rule 7).
///
/// Tidak ada pemantau koneksi: saat internet kembali, pengiriman terjadi di
/// ketukan timer berikutnya (paling lama [interval]) atau saat aplikasi
/// dibuka kembali. SyncBloc murah dipanggil: tanpa antrean, ia tidak
/// mengubah apa pun.
class SyncScheduler extends StatefulWidget {
  const SyncScheduler({
    super.key,
    required this.child,
    this.interval = const Duration(seconds: 30),
  });

  final Widget child;
  final Duration interval;

  @override
  State<SyncScheduler> createState() => _SyncSchedulerState();
}

class _SyncSchedulerState extends State<SyncScheduler>
    with WidgetsBindingObserver {
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _timer = Timer.periodic(widget.interval, (_) => _request());
  }

  @override
  void dispose() {
    _timer?.cancel();
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) _request();
  }

  void _request() {
    if (!mounted) return;
    context.read<SyncBloc>().add(const SyncRequested());
  }

  @override
  Widget build(BuildContext context) => widget.child;
}
