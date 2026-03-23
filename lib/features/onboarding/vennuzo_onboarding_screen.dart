import 'package:flutter/material.dart';

import '../../core/theme/vennuzo_theme.dart';
import '../../core/theme/theme_extensions.dart';

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
      title: 'Find what’s next',
      body:
          'Browse events near you—concerts, parties, meetups. Curated so you don’t miss the good ones.',
      statLabel: 'Curated picks',
      statValue: 'One place for events',
      accent: _SlideAccent.primary,
      icon: Icons.explore_rounded,
    ),
    _OnboardingSlideData(
      badge: 'Attend',
      title: 'Get in fast',
      body:
          'Book tickets in one flow. Instant confirmation and easy checkout so you’re in without the hassle.',
      statLabel: 'Ticketing',
      statValue: 'Simple & quick',
      accent: _SlideAccent.accent,
      icon: Icons.confirmation_num_rounded,
    ),
    _OnboardingSlideData(
      badge: 'Connect',
      title: 'Stay in the loop',
      body:
          'Share with friends and get updates from organizers. Events are better when you’re connected.',
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
          final heroHeight = compact ? 200.0 : 240.0;
          final paddingH = compact ? 20.0 : 24.0;
          final paddingV = compact ? 16.0 : 24.0;

          return AnimatedContainer(
            duration: const Duration(milliseconds: 400),
            curve: Curves.easeOutCubic,
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: [
                  palette.canvas,
                  Colors.white,
                  accent.withValues(alpha: 0.06),
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
                  compact ? 20 : 28,
                ),
                child: Column(
                  children: [
                    _OnboardingHeader(
                      onSkip: _isFinishing ? null : _finish,
                    ),
                    SizedBox(height: compact ? 20 : 28),
                    _OnboardingHero(
                      slide: slide,
                      height: heroHeight,
                      compact: compact,
                    ),
                    SizedBox(height: compact ? 20 : 24),
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
                    SizedBox(height: compact ? 16 : 20),
                    _PageIndicator(
                      count: _slides.length,
                      current: _currentIndex,
                      accent: accent,
                      palette: palette,
                    ),
                    SizedBox(height: compact ? 20 : 24),
                    FilledButton(
                      onPressed: _isFinishing
                          ? null
                          : isLast
                              ? _finish
                              : _next,
                      style: FilledButton.styleFrom(
                        minimumSize: const Size(double.infinity, 52),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(16),
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
                    if (!isLast) ...[
                      const SizedBox(height: 12),
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
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(999),
            boxShadow: [
              BoxShadow(
                color: palette.primaryStart.withValues(alpha: 0.1),
                blurRadius: 20,
                offset: const Offset(0, 6),
              ),
            ],
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
  });

  final _OnboardingSlideData slide;
  final double height;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final accent = slide.resolveAccent(palette);

    return AnimatedContainer(
      duration: const Duration(milliseconds: 400),
      curve: Curves.easeOutCubic,
      height: height,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(28),
        boxShadow: [
          BoxShadow(
            color: accent.withValues(alpha: 0.2),
            blurRadius: 32,
            offset: const Offset(0, 12),
          ),
          BoxShadow(
            color: VennuzoTheme.shadow.withValues(alpha: 0.06),
            blurRadius: 24,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(28),
        child: Stack(
          fit: StackFit.expand,
          children: [
            DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [
                    accent,
                    accent.withValues(alpha: 0.85),
                    HSLColor.fromColor(accent)
                        .withLightness(0.45)
                        .withSaturation(0.5)
                        .toColor(),
                  ],
                ),
              ),
            ),
            Positioned(
              top: -40,
              right: -40,
              child: Container(
                width: 160,
                height: 160,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: Colors.white.withValues(alpha: 0.12),
                ),
              ),
            ),
            Positioned(
              bottom: -60,
              left: -40,
              child: Container(
                width: 180,
                height: 180,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: Colors.white.withValues(alpha: 0.08),
                ),
              ),
            ),
            Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Container(
                    width: compact ? 80 : 96,
                    height: compact ? 80 : 96,
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.22),
                      borderRadius: BorderRadius.circular(24),
                    ),
                    child: Icon(
                      slide.icon,
                      size: compact ? 40 : 48,
                      color: Colors.white,
                    ),
                  ),
                  SizedBox(height: compact ? 14 : 18),
                  Text(
                    slide.badge,
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(
                          color: Colors.white.withValues(alpha: 0.95),
                          fontWeight: FontWeight.w700,
                          letterSpacing: 0.5,
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
        (index) => AnimatedContainer(
          duration: const Duration(milliseconds: 280),
          curve: Curves.easeOutCubic,
          margin: EdgeInsets.only(right: index == count - 1 ? 0 : 10),
          width: index == current ? 28 : 10,
          height: 10,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(999),
            color: index == current
                ? accent
                : palette.ink.withValues(alpha: 0.18),
          ),
        ),
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
        padding: EdgeInsets.symmetric(horizontal: compact ? 4 : 8),
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
            SizedBox(height: compact ? 10 : 14),
            Text(
              item.body,
              style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                    color: palette.slate,
                    height: 1.5,
                    fontSize: compact ? 15 : 16,
                  ),
            ),
            SizedBox(height: compact ? 20 : 24),
            Container(
              width: double.infinity,
              padding: EdgeInsets.all(compact ? 18 : 22),
              decoration: BoxDecoration(
                color: accent.withValues(alpha: 0.08),
                borderRadius: BorderRadius.circular(20),
                border: Border.all(
                  color: accent.withValues(alpha: 0.2),
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
                          style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                                color: palette.slate,
                                fontWeight: FontWeight.w600,
                              ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          item.statValue,
                          style: Theme.of(context).textTheme.titleLarge?.copyWith(
                                fontSize: compact ? 18 : 20,
                                fontWeight: FontWeight.w800,
                                color: palette.ink,
                              ),
                        ),
                      ],
                    ),
                  ),
                  Container(
                    width: 48,
                    height: 48,
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(14),
                      boxShadow: [
                        BoxShadow(
                          color: VennuzoTheme.shadow.withValues(alpha: 0.08),
                          blurRadius: 12,
                          offset: const Offset(0, 4),
                        ),
                      ],
                    ),
                    child: Icon(item.icon, color: accent, size: 26),
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
