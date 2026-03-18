import 'package:flutter/material.dart';

import '../../core/theme/eventora_theme.dart';
import '../../core/theme/theme_extensions.dart';
import '../../widgets/eventora_splash_stage.dart';

class EventoraOnboardingScreen extends StatefulWidget {
  const EventoraOnboardingScreen({super.key, required this.onFinished});

  final Future<void> Function() onFinished;

  @override
  State<EventoraOnboardingScreen> createState() =>
      _EventoraOnboardingScreenState();
}

class _EventoraOnboardingScreenState extends State<EventoraOnboardingScreen> {
  final PageController _pageController = PageController();
  int _currentIndex = 0;
  bool _isFinishing = false;

  static const _slides = [
    _OnboardingSlideData(
      badge: 'Discover',
      title: 'Find the events everyone will be talking about.',
      body:
          'Explore premium experiences, nearby plans, and trending nights in one smooth feed built for fast decisions.',
      statLabel: 'Discover',
      statValue: 'Curated picks',
      accent: _SlideAccent.primary,
      icon: Icons.explore_outlined,
    ),
    _OnboardingSlideData(
      badge: 'Attend',
      title: 'RSVP, buy, and show up without friction.',
      body:
          'Move from event details to checkout and entry with wallet-ready tickets, reminders, and clear status updates.',
      statLabel: 'Ticketing',
      statValue: 'One flow',
      accent: _SlideAccent.accent,
      icon: Icons.confirmation_num_outlined,
    ),
    _OnboardingSlideData(
      badge: 'Connect',
      title: 'Stay close to the schedule, crowd, and conversation.',
      body:
          'Eventora keeps your plans, updates, and community moments together so event day feels effortless.',
      statLabel: 'Experience',
      statValue: 'Social by design',
      accent: _SlideAccent.secondary,
      icon: Icons.forum_outlined,
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

    return Scaffold(
      body: LayoutBuilder(
        builder: (context, constraints) {
          final compact = constraints.maxHeight < 780;
          final heroHeight = compact ? 170.0 : 210.0;
          final outerPadding = compact ? 16.0 : 20.0;

          return Container(
            decoration: BoxDecoration(
              color: palette.canvas,
              gradient: LinearGradient(
                colors: [
                  palette.canvas,
                  Colors.white,
                  slide.resolveAccent(palette).withValues(alpha: 0.14),
                ],
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
              ),
            ),
            child: SafeArea(
              child: Padding(
                padding: EdgeInsets.fromLTRB(
                  outerPadding,
                  compact ? 14 : 20,
                  outerPadding,
                  compact ? 18 : 28,
                ),
                child: Column(
                  children: [
                    Row(
                      children: [
                        Container(
                          padding: EdgeInsets.symmetric(
                            horizontal: compact ? 10 : 12,
                            vertical: compact ? 7 : 8,
                          ),
                          decoration: BoxDecoration(
                            color: Colors.white,
                            borderRadius: BorderRadius.circular(999),
                            border: Border.all(color: palette.border),
                            boxShadow: [
                              BoxShadow(
                                color: palette.primaryStart.withValues(
                                  alpha: 0.08,
                                ),
                                blurRadius: 18,
                                offset: const Offset(0, 10),
                              ),
                            ],
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(
                                Icons.confirmation_num_rounded,
                                size: compact ? 16 : 18,
                                color: palette.primaryStart,
                              ),
                              SizedBox(width: compact ? 6 : 8),
                              Text(
                                'Eventora',
                                style: context.text.bodyMedium?.copyWith(
                                  color: palette.ink,
                                  fontWeight: FontWeight.w800,
                                ),
                              ),
                            ],
                          ),
                        ),
                        const Spacer(),
                        TextButton(
                          onPressed: _isFinishing ? null : _finish,
                          child: const Text('Skip'),
                        ),
                      ],
                    ),
                    SizedBox(height: compact ? 12 : 18),
                    Expanded(
                      child: Column(
                        children: [
                          SizedBox(
                            height: heroHeight,
                            child: IgnorePointer(
                              child: ClipRRect(
                                borderRadius: BorderRadius.circular(
                                  compact ? 26 : 32,
                                ),
                                child: const EventoraSplashStage(
                                  title: 'Eventora',
                                  subtitle: 'Experience events differently',
                                ),
                              ),
                            ),
                          ),
                          SizedBox(height: compact ? 12 : 18),
                          Expanded(
                            child: PageView.builder(
                              controller: _pageController,
                              itemCount: _slides.length,
                              onPageChanged: (index) {
                                setState(() => _currentIndex = index);
                              },
                              itemBuilder: (context, index) {
                                final item = _slides[index];
                                return _OnboardingSlide(
                                  item: item,
                                  compact: compact,
                                );
                              },
                            ),
                          ),
                        ],
                      ),
                    ),
                    SizedBox(height: compact ? 12 : 18),
                    Row(
                      children: List.generate(
                        _slides.length,
                        (index) => AnimatedContainer(
                          duration: const Duration(milliseconds: 220),
                          curve: Curves.easeOut,
                          margin: EdgeInsets.only(
                            right: index == _slides.length - 1 ? 0 : 8,
                          ),
                          width: index == _currentIndex ? 28 : 10,
                          height: 10,
                          decoration: BoxDecoration(
                            borderRadius: BorderRadius.circular(999),
                            color: index == _currentIndex
                                ? slide.resolveAccent(palette)
                                : palette.ink.withValues(alpha: 0.14),
                          ),
                        ),
                      ),
                    ),
                    SizedBox(height: compact ? 12 : 18),
                    SizedBox(
                      width: double.infinity,
                      child: ElevatedButton(
                        onPressed: _isFinishing
                            ? null
                            : isLast
                            ? _finish
                            : _next,
                        child: Text(
                          _isFinishing
                              ? 'Opening Eventora...'
                              : isLast
                              ? 'Start exploring'
                              : 'Continue',
                        ),
                      ),
                    ),
                    const SizedBox(height: 10),
                    SizedBox(
                      width: double.infinity,
                      child: OutlinedButton(
                        onPressed: _isFinishing
                            ? null
                            : isLast
                            ? _finish
                            : () => _pageController.animateToPage(
                                _slides.length - 1,
                                duration: const Duration(milliseconds: 280),
                                curve: Curves.easeOutCubic,
                              ),
                        child: Text(isLast ? 'Maybe later' : 'Jump to the end'),
                      ),
                    ),
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
      duration: const Duration(milliseconds: 280),
      curve: Curves.easeOutCubic,
    );
  }

  Future<void> _finish() async {
    if (_isFinishing) {
      return;
    }
    setState(() => _isFinishing = true);
    await widget.onFinished();
    if (mounted) {
      setState(() => _isFinishing = false);
    }
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

    return LayoutBuilder(
      builder: (context, constraints) {
        return Container(
          width: double.infinity,
          padding: EdgeInsets.all(compact ? 22 : 28),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(compact ? 24 : 28),
            color: Colors.white,
            border: Border.all(color: palette.border),
            boxShadow: [
              BoxShadow(
                color: palette.primaryStart.withValues(alpha: 0.08),
                blurRadius: 32,
                offset: const Offset(0, 18),
              ),
            ],
          ),
          child: SingleChildScrollView(
            child: ConstrainedBox(
              constraints: BoxConstraints(
                minHeight: constraints.maxHeight - (compact ? 44 : 56),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    padding: EdgeInsets.symmetric(
                      horizontal: compact ? 10 : 12,
                      vertical: compact ? 7 : 8,
                    ),
                    decoration: BoxDecoration(
                      color: accent.withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(999),
                    ),
                    child: Text(
                      item.badge,
                      style: context.text.bodyMedium?.copyWith(
                        color: accent,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ),
                  SizedBox(height: compact ? 14 : 18),
                  Container(
                    width: compact ? 60 : 68,
                    height: compact ? 60 : 68,
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(compact ? 18 : 22),
                      gradient: LinearGradient(
                        colors: [
                          accent.withValues(alpha: 0.14),
                          accent.withValues(alpha: 0.22),
                        ],
                      ),
                    ),
                    child: Icon(
                      item.icon,
                      size: compact ? 28 : 32,
                      color: accent,
                    ),
                  ),
                  SizedBox(height: compact ? 16 : 22),
                  Text(
                    item.title,
                    style:
                        (compact
                                ? context.text.titleLarge?.copyWith(
                                    fontSize: 20,
                                  )
                                : context.text.headlineSmall)
                            ?.copyWith(height: 1.04),
                  ),
                  SizedBox(height: compact ? 10 : 12),
                  Text(
                    item.body,
                    style:
                        (compact
                                ? context.text.bodyMedium?.copyWith(
                                    fontSize: 13,
                                  )
                                : context.text.bodyLarge)
                            ?.copyWith(
                              color: palette.ink.withValues(alpha: 0.86),
                            ),
                  ),
                  SizedBox(height: compact ? 16 : 24),
                  Container(
                    width: double.infinity,
                    padding: EdgeInsets.all(compact ? 14 : 18),
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        colors: [
                          palette.primaryStart.withValues(alpha: 0.08),
                          palette.primaryEnd.withValues(alpha: 0.08),
                        ],
                      ),
                      borderRadius: BorderRadius.circular(compact ? 18 : 22),
                      border: Border.all(color: palette.border),
                    ),
                    child: Row(
                      children: [
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                item.statLabel,
                                style: context.text.bodyMedium?.copyWith(
                                  color: palette.slate,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                              const SizedBox(height: 6),
                              Text(
                                item.statValue,
                                style: context.text.titleLarge?.copyWith(
                                  fontSize: compact ? 18 : 20,
                                ),
                              ),
                            ],
                          ),
                        ),
                        Container(
                          width: compact ? 42 : 48,
                          height: compact ? 42 : 48,
                          decoration: BoxDecoration(
                            color: Colors.white,
                            borderRadius: BorderRadius.circular(16),
                          ),
                          child: Icon(item.icon, color: accent),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      },
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

  Color resolveAccent(EventoraPalette palette) {
    return switch (accent) {
      _SlideAccent.primary => palette.primaryStart,
      _SlideAccent.accent => palette.coral,
      _SlideAccent.secondary => palette.gold,
    };
  }
}
