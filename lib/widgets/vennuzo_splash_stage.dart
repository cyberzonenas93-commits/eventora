import 'package:flutter/material.dart';

import '../core/theme/theme_extensions.dart';

class VennuzoSplashStage extends StatefulWidget {
  const VennuzoSplashStage({
    super.key,
    this.title = 'Vennuzo',
    this.subtitle = 'Experience events differently',
    this.showLoader = false,
  });

  final String title;
  final String? subtitle;
  final bool showLoader;

  @override
  State<VennuzoSplashStage> createState() => _VennuzoSplashStageState();
}

class _VennuzoSplashStageState extends State<VennuzoSplashStage>
    with SingleTickerProviderStateMixin {
  late final AnimationController _glowController = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1700),
  )..repeat(reverse: true);

  @override
  void dispose() {
    _glowController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;

    return LayoutBuilder(
      builder: (context, constraints) {
        final compact = constraints.maxHeight < 220;
        final badgeSize = compact ? 92.0 : 126.0;
        final titleStyle = compact
            ? context.text.headlineSmall
            : context.text.headlineMedium;
        final subtitleStyle = compact
            ? context.text.bodyMedium
            : context.text.bodyLarge;

        return DecoratedBox(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              colors: [palette.primaryStart, palette.primaryEnd],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
          ),
          child: Stack(
            fit: StackFit.expand,
            children: [
              Positioned(
                top: compact ? -70 : -110,
                right: compact ? -50 : -70,
                child: _GlowOrb(
                  color: Colors.white.withValues(alpha: 0.18),
                  size: compact ? 180 : 260,
                ),
              ),
              Positioned(
                bottom: compact ? -80 : -120,
                left: compact ? -50 : -60,
                child: _GlowOrb(
                  color: Colors.white.withValues(alpha: 0.12),
                  size: compact ? 190 : 280,
                ),
              ),
              Center(
                child: Padding(
                  padding: EdgeInsets.symmetric(
                    horizontal: compact ? 18 : 24,
                    vertical: compact ? 14 : 20,
                  ),
                  child: TweenAnimationBuilder<double>(
                    tween: Tween(begin: 0.9, end: 1),
                    duration: const Duration(milliseconds: 300),
                    curve: Curves.easeOutCubic,
                    builder: (context, scale, child) {
                      return AnimatedOpacity(
                        duration: const Duration(milliseconds: 300),
                        opacity: 1,
                        child: Transform.scale(scale: scale, child: child),
                      );
                    },
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        AnimatedBuilder(
                          animation: _glowController,
                          builder: (context, child) {
                            final glow = Tween<double>(
                              begin: compact ? 18 : 26,
                              end: compact ? 28 : 40,
                            ).transform(_glowController.value);
                            return SizedBox(
                              width: badgeSize,
                              height: badgeSize,
                              child: Stack(
                                alignment: Alignment.center,
                                children: [
                                  Container(
                                    width: compact ? 56 : 72,
                                    height: compact ? 56 : 72,
                                    decoration: BoxDecoration(
                                      shape: BoxShape.circle,
                                      boxShadow: [
                                        BoxShadow(
                                          color: Colors.white.withValues(
                                            alpha: 0.24,
                                          ),
                                          blurRadius: glow,
                                          spreadRadius: 4,
                                        ),
                                      ],
                                    ),
                                  ),
                                  Icon(
                                    Icons.confirmation_num_rounded,
                                    size: compact ? 52 : 68,
                                    color: Colors.white,
                                  ),
                                  Positioned(
                                    top: compact ? 18 : 26,
                                    right: compact ? 16 : 24,
                                    child: Icon(
                                      Icons.auto_awesome_rounded,
                                      size: compact ? 12 : 16,
                                      color: Colors.white.withValues(
                                        alpha: 0.92,
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            );
                          },
                        ),
                        SizedBox(height: compact ? 14 : 24),
                        Text(
                          widget.title,
                          style: titleStyle?.copyWith(color: Colors.white),
                          textAlign: TextAlign.center,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        if ((widget.subtitle ?? '').isNotEmpty) ...[
                          SizedBox(height: compact ? 6 : 10),
                          Text(
                            widget.subtitle!,
                            style: subtitleStyle?.copyWith(
                              color: Colors.white.withValues(alpha: 0.9),
                            ),
                            textAlign: TextAlign.center,
                            maxLines: compact ? 1 : 2,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ],
                        if (widget.showLoader) ...[
                          SizedBox(height: compact ? 16 : 28),
                          SizedBox(
                            width: compact ? 22 : 26,
                            height: compact ? 22 : 26,
                            child: CircularProgressIndicator(
                              strokeWidth: 2.4,
                              color: Colors.white.withValues(alpha: 0.92),
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

class _GlowOrb extends StatelessWidget {
  const _GlowOrb({required this.color, required this.size});

  final Color color;
  final double size;

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      child: Container(
        width: size,
        height: size,
        decoration: BoxDecoration(shape: BoxShape.circle, color: color),
      ),
    );
  }
}
