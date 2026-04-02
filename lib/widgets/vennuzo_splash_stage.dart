import 'package:flutter/material.dart';

import '../core/art/event_art_widget.dart';
import '../core/art/mood_art_palette.dart';
import '../core/theme/vennuzo_theme.dart';
import '../core/theme/theme_extensions.dart';
import '../domain/models/event_models.dart';

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
            : context.text.headlineLarge;
        final subtitleStyle = compact
            ? context.text.bodyMedium
            : context.text.bodyLarge;

        return Stack(
          fit: StackFit.expand,
          children: [
            // Generative art background
            GenerativeArt(
              seed: 42,
              mood: EventMood.night,
              palette: MoodArtPalette(
                base: palette.primaryStart,
                mid: Color.lerp(palette.primaryStart, palette.primaryEnd, 0.5)!,
                highlight: palette.primaryEnd,
                pop: palette.coral,
                overlay: palette.gold,
                accent: Colors.white,
              ),
              height: constraints.maxHeight,
              width: constraints.maxWidth,
              intensity: 0.8,
            ),
            // Deeper, cinematic 3-stop radial scrim
            DecoratedBox(
              decoration: BoxDecoration(
                gradient: RadialGradient(
                  center: Alignment.center,
                  radius: 1.2,
                  colors: [
                    Colors.black.withValues(alpha: 0.10),
                    Colors.black.withValues(alpha: 0.28),
                    Colors.black.withValues(alpha: 0.45),
                  ],
                  stops: const [0.0, 0.55, 1.0],
                ),
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
                            begin: compact ? 12 : 18,
                            end: compact ? 22 : 30,
                          ).transform(_glowController.value);
                          final logoSize = compact ? 120.0 : 180.0;
                          return Container(
                            width: logoSize,
                            height: logoSize,
                            decoration: BoxDecoration(
                              boxShadow: [
                                BoxShadow(
                                  color: const Color(0xFF7B8CFF)
                                      .withValues(alpha: 0.18),
                                  blurRadius: glow,
                                  spreadRadius: 2,
                                ),
                              ],
                            ),
                            child: Image.asset(
                              'assets/logo-transparent.png',
                              fit: BoxFit.contain,
                              gaplessPlayback: true,
                              frameBuilder: (context, child, frame, loaded) {
                                if (frame == null) {
                                  return Center(
                                    child: Text(
                                      'V',
                                      style: TextStyle(
                                        fontFamily: 'Sora',
                                        fontSize: compact ? 48 : 64,
                                        fontWeight: FontWeight.w800,
                                        color: const Color(0xFF7B8CFF),
                                      ),
                                    ),
                                  );
                                }
                                return AnimatedOpacity(
                                  opacity: loaded ? 1.0 : 0.0,
                                  duration: const Duration(milliseconds: 300),
                                  child: child,
                                );
                              },
                            ),
                          );
                        },
                      ),
                      SizedBox(height: compact ? 14 : 24),
                      Text(
                        widget.title,
                        style: titleStyle?.copyWith(
                          color: Colors.white,
                          letterSpacing: -0.5,
                          shadows: [
                            Shadow(
                              color: Colors.black.withValues(alpha: 0.3),
                              blurRadius: 10,
                            ),
                          ],
                        ),
                        textAlign: TextAlign.center,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      if ((widget.subtitle ?? '').isNotEmpty) ...[
                        SizedBox(height: compact ? 6 : 10),
                        Opacity(
                          opacity: 0.85,
                          child: Text(
                            widget.subtitle!,
                            style: subtitleStyle?.copyWith(
                              color: Colors.white,
                            ),
                            textAlign: TextAlign.center,
                            maxLines: compact ? 1 : 2,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      ],
                      if (widget.showLoader) ...[
                        SizedBox(height: compact ? 16 : 28),
                        SizedBox(
                          width: compact ? 24 : 28,
                          height: compact ? 24 : 28,
                          child: CircularProgressIndicator(
                            strokeWidth: 2.0,
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
        );
      },
    );
  }
}
