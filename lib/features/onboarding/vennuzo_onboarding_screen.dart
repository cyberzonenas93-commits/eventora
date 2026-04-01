import 'package:flutter/material.dart';

import '../../core/art/art_seed.dart';
import '../../core/art/event_art_widget.dart';
import '../../core/art/mood_art_palette.dart';
import '../../core/theme/vennuzo_theme.dart';
import '../../core/theme/theme_extensions.dart';
import '../../domain/models/event_models.dart';

class VennuzoOnboardingScreen extends StatefulWidget {
  const VennuzoOnboardingScreen({super.key, required this.onFinished});

  final Future<void> Function() onFinished;

  @override
  State<VennuzoOnboardingScreen> createState() =>
      _VennuzoOnboardingScreenState();
}

class _VennuzoOnboardingScreenState extends State<VennuzoOnboardingScreen> {
  final PageController _pageController = PageController();
  int _currentIndex = 0;
  bool _isFinishing = false;

  static const _slides = [
    _OnboardingSlideData(
      badge: 'Discover',
      title: 'Find what\u2019s next',
      body:
          'Browse events near you\u2014concerts, parties, meetups. Curated so you don\u2019t miss the good ones.',
      statLabel: 'Curated picks',
      statValue: 'One place for events',
      accent: _SlideAccent.primary,
      icon: Icons.explore_rounded,
    ),
    _OnboardingSlideData(
      badge: 'Attend',
      title: 'Get in fast',
      body:
          'Book tickets in one flow. Instant confirmation and easy checkout so you\u2019re in without the hassle.',
      statLabel: 'Ticketing',
      statValue: 'Simple & quick',
      accent: _SlideAccent.accent,
      icon: Icons.confirmation_num_rounded,
    ),
    _OnboardingSlideData(
      badge: 'Connect',
      title: 'Stay in the loop',
      body:
          'Share with friends and get updates from organizers. Events are better when you\u2019re connected.',
      statLabel: 'Experience',
      statValue: 'Social by design',
      accent: _SlideAccent.secondary,
      icon: Icons.people_rounded,
    ),
  ];

  @override
  void dispose() {
    _pageController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final slide = _slides[_currentIndex];
    final isLast = _currentIndex == _slides.length - 1;
    final accent = slide.resolveAccent(palette);

    return Scaffold(
      body: LayoutBuilder(
        builder: (context, constraints) {
          final compact = constraints.maxHeight < 720;
          final heroHeight = compact ? 220.0 : 260.0;
          final paddingH = compact ? 22.0 : 28.0;
          final paddingV = compact ? 18.0 : 28.0;

          return AnimatedContainer(
            duration: const Duration(milliseconds: 400),
            curve: Curves.easeOutCubic,
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: [
                  palette.canvas,
                  Colors.white,
                  accent.withValues(alpha: 0.05),
                ],
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
              ),
            ),
            child: SafeArea(
              child: Padding(
                padding: EdgeInsets.fromLTRB(
                  paddingH,
                  paddingV,
                  paddingH,
                  compact ? 22 : 32,
                ),
                child: Column(
                  children: [
                    _OnboardingHeader(
                      onSkip: _isFinishing ? null : _finish,
                    ),
                    SizedBox(height: compact ? 24 : 32),
                    _OnboardingHero(
                      slide: slide,
                      height: heroHeight,
                      compact: compact,
                      slideIndex: _currentIndex,
                    ),
                    SizedBox(height: compact ? 24 : 28),
                    Expanded(
                      child: PageView.builder(
                        controller: _pageController,
                        itemCount: _slides.length,
                        onPageChanged: (index) {
                          setState(() => _currentIndex = index);
                        },
                        itemBuilder: (context, index) {
                          return _OnboardingSlide(
                            item: _slides[index],
                            compact: compact,
                          );
                        },
                      ),
                    ),
                    SizedBox(height: compact ? 18 : 24),
                    _PageIndicator(
                      count: _slides.length,
                      current: _currentIndex,
                      accent: accent,
                      palette: palette,
                    ),
                    SizedBox(height: compact ? 24 : 28),
                    DecoratedBox(
                      decoration: BoxDecoration(
                        borderRadius:
                            BorderRadius.circular(VennuzoTheme.radiusMd),
                        gradient: LinearGradient(
                          colors: [
                            palette.primaryStart,
                            palette.primaryMid,
                            palette.primaryEnd,
                          ],
                          begin: Alignment.centerLeft,
                          end: Alignment.centerRight,
                        ),
                      ),
                      child: FilledButton(
                        onPressed: _isFinishing
                            ? null
                            : isLast
                                ? _finish
                                : _next,
                        style: FilledButton.styleFrom(
                          minimumSize: const Size(double.infinity, 54),
                          backgroundColor: Colors.transparent,
                          shadowColor: Colors.transparent,
                          shape: RoundedRectangleBorder(
                            borderRadius:
                                BorderRadius.circular(VennuzoTheme.radiusMd),
                          ),
                          textStyle: const TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        child: Text(
                          _isFinishing
                              ? 'Opening Vennuzo...'
                              : isLast
                                  ? 'Start exploring'
                                  : 'Continue',
                        ),
                      ),
                    ),
                    if (!isLast) ...[
                      const SizedBox(height: 14),
                      TextButton(
                        onPressed: _isFinishing ? null : _finish,
                        child: Text(
                          'Skip',
                          style: TextStyle(
                            color: palette.slate,
                            fontSize: 15,
                          ),
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ),
          );
        },
      ),
    );
  }

  Future<void> _next() async {
    await _pageController.nextPage(
      duration: const Duration(milliseconds: 320),
      curve: Curves.easeOutCubic,
    );
  }

  Future<void> _finish() async {
    if (_isFinishing) return;
    setState(() => _isFinishing = true);
    await widget.onFinished();
    if (mounted) setState(() => _isFinishing = false);
  }
}

class _OnboardingHeader extends StatelessWidget {
  const _OnboardingHeader({this.onSkip});

  final VoidCallback? onSkip;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;

    return Row(
      children: [
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(VennuzoTheme.radiusFull),
            boxShadow: VennuzoTheme.shadowResting,
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                Icons.confirmation_num_rounded,
                size: 20,
                color: palette.primaryStart,
              ),
              const SizedBox(width: 8),
              Text(
                'Vennuzo',
                style: Theme.of(context).textTheme.titleMedium?.copyWith(
                      color: palette.ink,
                      fontWeight: FontWeight.w800,
                    ),
              ),
            ],
          ),
        ),
        const Spacer(),
        if (onSkip != null)
          TextButton(
            onPressed: onSkip,
            child: Text(
              'Skip',
              style: TextStyle(
                color: palette.slate,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
      ],
    );
  }
}

class _OnboardingHero extends StatelessWidget {
  const _OnboardingHero({
    required this.slide,
    required this.height,
    required this.compact,
    required this.slideIndex,
  });

  final _OnboardingSlideData slide;
  final double height;
  final bool compact;
  final int slideIndex;

  // Vibrant palettes per slide -- hand-tuned for visual punch
  static const _slidePalettes = [
    // Discover -- indigo / electric blue
    MoodArtPalette(
      base: Color(0xFF1A1A5E),
      mid: Color(0xFF4F46E5),
      highlight: Color(0xFF818CF8),
      pop: Color(0xFF06B6D4),
      overlay: Color(0xFF312E81),
      accent: Color(0xFFC7D2FE),
    ),
    // Attend -- coral / warm rose
    MoodArtPalette(
      base: Color(0xFF7F1D1D),
      mid: Color(0xFFF43F5E),
      highlight: Color(0xFFFB7185),
      pop: Color(0xFFFBBF24),
      overlay: Color(0xFF9F1239),
      accent: Color(0xFFFFE4E6),
    ),
    // Connect -- violet / purple
    MoodArtPalette(
      base: Color(0xFF3B0764),
      mid: Color(0xFF8B5CF6),
      highlight: Color(0xFFA78BFA),
      pop: Color(0xFFF472B6),
      overlay: Color(0xFF581C87),
      accent: Color(0xFFEDE9FE),
    ),
  ];

  @override
  Widget build(BuildContext context) {
    final artPalette = _slidePalettes[slideIndex % _slidePalettes.length];
    final moods = [EventMood.night, EventMood.sunrise, EventMood.electric];
    final artMood = moods[slideIndex % moods.length];

    return AnimatedContainer(
      duration: const Duration(milliseconds: 400),
      curve: Curves.easeOutCubic,
      height: height,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(VennuzoTheme.radiusXl),
        boxShadow: [
          BoxShadow(
            color: artPalette.mid.withValues(alpha: 0.35),
            blurRadius: 36,
            offset: const Offset(0, 14),
          ),
          BoxShadow(
            color: VennuzoTheme.shadow.withValues(alpha: 0.08),
            blurRadius: 28,
            offset: const Offset(0, 10),
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(VennuzoTheme.radiusXl),
        child: Stack(
          fit: StackFit.expand,
          children: [
            // Generative art with vibrant palette -- deeper intensity
            GenerativeArt(
              seed: ArtSeed.combine(slideIndex * 9973, 77731),
              mood: artMood,
              palette: artPalette,
              height: height,
              intensity: 1.4,
            ),
            // Richer scrim for depth
            DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [
                    Colors.black.withValues(alpha: 0.05),
                    Colors.black.withValues(alpha: 0.15),
                    Colors.black.withValues(alpha: 0.35),
                  ],
                  stops: const [0.0, 0.5, 1.0],
                ),
              ),
            ),
            Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  // Icon above text
                  Container(
                    width: compact ? 64 : 76,
                    height: compact ? 64 : 76,
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.15),
                      borderRadius: BorderRadius.circular(22),
                      border: Border.all(
                        color: Colors.white.withValues(alpha: 0.22),
                      ),
                    ),
                    child: Icon(
                      slide.icon,
                      size: compact ? 32 : 38,
                      color: Colors.white,
                    ),
                  ),
                  SizedBox(height: compact ? 14 : 18),
                  Text(
                    slide.badge,
                    style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                          color: Colors.white,
                          fontWeight: FontWeight.w800,
                          letterSpacing: 1.0,
                          shadows: [
                            Shadow(
                              color: Colors.black.withValues(alpha: 0.4),
                              blurRadius: 14,
                            ),
                          ],
                        ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _PageIndicator extends StatelessWidget {
  const _PageIndicator({
    required this.count,
    required this.current,
    required this.accent,
    required this.palette,
  });

  final int count;
  final int current;
  final Color accent;
  final VennuzoPalette palette;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: List.generate(
        count,
        (index) {
          final isActive = index == current;
          return AnimatedContainer(
            duration: const Duration(milliseconds: 300),
            curve: Curves.easeOutCubic,
            margin: EdgeInsets.only(right: index == count - 1 ? 0 : 10),
            width: isActive ? 32 : 8,
            height: 8,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(VennuzoTheme.radiusFull),
              color: isActive
                  ? accent
                  : palette.ink.withValues(alpha: 0.14),
            ),
          );
        },
      ),
    );
  }
}

class _OnboardingSlide extends StatelessWidget {
  const _OnboardingSlide({required this.item, required this.compact});

  final _OnboardingSlideData item;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final accent = item.resolveAccent(palette);

    return SingleChildScrollView(
      child: Padding(
        padding: EdgeInsets.symmetric(horizontal: compact ? 4 : 10),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              item.title,
              style: (compact
                      ? Theme.of(context).textTheme.titleLarge?.copyWith(
                          fontSize: 22,
                          height: 1.2,
                        )
                      : Theme.of(context).textTheme.headlineSmall)
                  ?.copyWith(
                fontWeight: FontWeight.w800,
                color: palette.ink,
                letterSpacing: -0.3,
              ),
            ),
            SizedBox(height: compact ? 12 : 16),
            Text(
              item.body,
              style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                    color: palette.slate,
                    height: 1.55,
                    fontSize: compact ? 15 : 16,
                  ),
            ),
            SizedBox(height: compact ? 22 : 28),
            Container(
              width: double.infinity,
              padding: EdgeInsets.all(compact ? 20 : 24),
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: [
                    accent.withValues(alpha: 0.07),
                    accent.withValues(alpha: 0.03),
                  ],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
                borderRadius:
                    BorderRadius.circular(VennuzoTheme.radiusLg),
                border: Border.all(
                  color: accent.withValues(alpha: 0.16),
                  width: 1,
                ),
              ),
              child: Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          item.statLabel,
                          style: Theme.of(context)
                              .textTheme
                              .bodyMedium
                              ?.copyWith(
                                color: palette.slate,
                                fontWeight: FontWeight.w600,
                              ),
                        ),
                        const SizedBox(height: 6),
                        Text(
                          item.statValue,
                          style: Theme.of(context)
                              .textTheme
                              .titleLarge
                              ?.copyWith(
                                fontSize: compact ? 18 : 20,
                                fontWeight: FontWeight.w800,
                                color: palette.ink,
                              ),
                        ),
                      ],
                    ),
                  ),
                  Container(
                    width: 50,
                    height: 50,
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(15),
                      boxShadow: [
                        BoxShadow(
                          color: VennuzoTheme.shadow.withValues(alpha: 0.08),
                          blurRadius: 12,
                          offset: const Offset(0, 4),
                        ),
                      ],
                    ),
                    child: GenerativeArt(
                      seed: ArtSeed.combine(item.badge.hashCode, 55337),
                      mood: EventMood.night,
                      palette: MoodArtPalette.fromAccent(accent),
                      height: 50,
                      width: 50,
                      borderRadius: BorderRadius.circular(15),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

enum _SlideAccent { primary, accent, secondary }

class _OnboardingSlideData {
  const _OnboardingSlideData({
    required this.badge,
    required this.title,
    required this.body,
    required this.statLabel,
    required this.statValue,
    required this.accent,
    required this.icon,
  });

  final String badge;
  final String title;
  final String body;
  final String statLabel;
  final String statValue;
  final _SlideAccent accent;
  final IconData icon;

  Color resolveAccent(VennuzoPalette palette) {
    return switch (accent) {
      _SlideAccent.primary => palette.primaryStart,
      _SlideAccent.accent => palette.coral,
      _SlideAccent.secondary => palette.gold,
    };
  }
}
