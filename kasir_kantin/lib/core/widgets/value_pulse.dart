import 'package:flutter/material.dart';

/// Umpan balik gerak halus saat [value] berubah: [child] membesar sedikit lalu
/// kembali (DESIGN.md §38: umpan balik jumlah keranjang, singkat, tanpa memantul).
///
/// Tidak menambah atau menduplikasi widget (tidak seperti AnimatedSwitcher),
/// jadi teks di dalamnya tetap satu dan mudah diuji. Pada kemunculan pertama
/// tidak ada animasi. Dimatikan bila sistem meminta animasi dikurangi.
class ValuePulse extends StatefulWidget {
  const ValuePulse({super.key, required this.value, required this.child});

  /// Nilai yang dipantau; animasi berjalan setiap kali nilainya berbeda.
  final Object value;
  final Widget child;

  static const duration = Duration(milliseconds: 160);

  @override
  State<ValuePulse> createState() => _ValuePulseState();
}

class _ValuePulseState extends State<ValuePulse>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: ValuePulse.duration,
  );

  // 1.0 -> 1.12 -> 1.0, satu denyut.
  late final Animation<double> _scale = TweenSequence<double>([
    TweenSequenceItem(
      tween: Tween<double>(
        begin: 1,
        end: 1.12,
      ).chain(CurveTween(curve: Curves.easeOut)),
      weight: 50,
    ),
    TweenSequenceItem(
      tween: Tween<double>(
        begin: 1.12,
        end: 1,
      ).chain(CurveTween(curve: Curves.easeIn)),
      weight: 50,
    ),
  ]).animate(_controller);

  @override
  void didUpdateWidget(ValuePulse oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.value != widget.value &&
        !MediaQuery.disableAnimationsOf(context)) {
      _controller.forward(from: 0);
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return ScaleTransition(scale: _scale, child: widget.child);
  }
}
