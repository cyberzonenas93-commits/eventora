import 'dart:async';

import 'package:flutter/material.dart';

class EventoraReveal extends StatefulWidget {
  const EventoraReveal({
    super.key,
    required this.child,
    this.delay = Duration.zero,
    this.duration = const Duration(milliseconds: 320),
    this.beginOffset = const Offset(0, 0.035),
    this.beginScale = 0.985,
  });

  final Widget child;
  final Duration delay;
  final Duration duration;
  final Offset beginOffset;
  final double beginScale;

  @override
  State<EventoraReveal> createState() => _EventoraRevealState();
}

class _EventoraRevealState extends State<EventoraReveal>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: widget.duration,
  );
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    if (widget.delay == Duration.zero) {
      _controller.forward();
    } else {
      _timer = Timer(widget.delay, () {
        if (mounted) {
          _controller.forward();
        }
      });
    }
  }

  @override
  void dispose() {
    _timer?.cancel();
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final curved = CurvedAnimation(
      parent: _controller,
      curve: Curves.easeOutCubic,
    );

    return FadeTransition(
      opacity: curved,
      child: AnimatedBuilder(
        animation: curved,
        child: widget.child,
        builder: (context, child) {
          final slide = Offset.lerp(
            widget.beginOffset,
            Offset.zero,
            curved.value,
          )!;
          final scale = Tween<double>(
            begin: widget.beginScale,
            end: 1,
          ).transform(curved.value);

          return Transform.translate(
            offset: Offset(0, slide.dy * 120),
            child: Transform.scale(scale: scale, child: child),
          );
        },
      ),
    );
  }
}
