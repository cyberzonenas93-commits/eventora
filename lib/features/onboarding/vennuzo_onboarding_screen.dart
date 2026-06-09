import 'package:flutter/material.dart';

import '../../core/theme/vennuzo_theme.dart';
import '../../core/theme/theme_extensions.dart';
import '../../core/visuals/vennuzo_visuals.dart';
import '../../data/services/vennuzo_launch_preferences.dart';
import '../../domain/models/event_models.dart';

class VennuzoOnboardingScreen extends StatefulWidget {
  const VennuzoOnboardingScreen({super.key, required this.onFinished});

  final Future<void> Function(VennuzoOnboardingPreferences preferences)
  onFinished;

  @override
  State<VennuzoOnboardingScreen> createState() =>
      _VennuzoOnboardingScreenState();
}

class _VennuzoOnboardingScreenState extends State<VennuzoOnboardingScreen> {
  final PageController _pageController = PageController();
  final TextEditingController _cityController = TextEditingController(
    text: 'Accra',
  );
  final Set<String> _selectedCategoryIds = <String>{
    'nightlife',
    'music_live',
    'corporate_professional',
  };
  int _currentIndex = 0;
  bool _isFinishing = false;
  bool _marketingOptIn = false;
  bool _promotionalPushEnabled = true;

  static const _slides = [
    _OnboardingSlideData(
      badge: 'Discover',
      title: 'Find the night faster',
      body:
          'Browse photo-led events, see what is close, and save the ones worth leaving the house for.',
      statLabel: 'Discovery',
      statValue: 'Photos, map, saves',
      imagePath: VennuzoVisuals.exploreSpotlight,
      caption: 'Curated live picks around you',
      accent: _SlideAccent.primary,
      icon: Icons.explore_rounded,
    ),
    _OnboardingSlideData(
      badge: 'Attend',
      title: 'Tickets that feel instant',
      body:
          'Book, pay, and keep your QR pass ready at the door without digging through emails.',
      statLabel: 'Ticketing',
      statValue: 'Checkout to QR',
      imagePath: VennuzoVisuals.checkoutTicket,
      caption: 'Fast entry when the room is full',
      accent: _SlideAccent.accent,
      icon: Icons.confirmation_num_rounded,
    ),
    _OnboardingSlideData(
      badge: 'Connect',
      title: 'Move with your people',
      body:
          'Share plans, follow updates, and keep the event conversation in one clean place.',
      statLabel: 'Social layer',
      statValue: 'Friends, posts, alerts',
      imagePath: VennuzoVisuals.creatorProfile,
      caption: 'Events are better with a crew',
      accent: _SlideAccent.secondary,
      icon: Icons.people_rounded,
    ),
    _OnboardingSlideData(
      badge: 'Create',
      title: 'Fill the room with less friction',
      body:
          'Hosts get event setup, promotions, check-in, and performance signals built into the same app.',
      statLabel: 'For creators',
      statValue: 'Launch, sell, measure',
      imagePath: VennuzoVisuals.organizerOps,
      caption: 'Tools for the people making the night happen',
      accent: _SlideAccent.primary,
      icon: Icons.auto_graph_rounded,
    ),
    _OnboardingSlideData(
      badge: 'Preferences',
      title: 'Choose your event world',
      body:
          'Tell Vennuzo what belongs in your feed, from nightlife and music to church, corporate, sales, family, tech, and travel experiences.',
      statLabel: 'Personalization',
      statValue: 'Every event type',
      imagePath: VennuzoVisuals.onboardingPreferences,
      caption: 'A feed shaped around the events you actually want',
      accent: _SlideAccent.secondary,
      icon: Icons.tune_rounded,
    ),
    _OnboardingSlideData(
      badge: 'Alerts',
      title: 'Keep promotions intentional',
      body:
          'Promotional pushes should match your selected categories, city, and creators you follow.',
      statLabel: 'Opt-in only',
      statValue: 'No platform-wide blasts',
      imagePath: VennuzoVisuals.campaignReach,
      caption: 'Sponsored events only when they match your lane',
      accent: _SlideAccent.accent,
      icon: Icons.notifications_active_rounded,
    ),
  ];

  static const _categorySlideIndex = 4;
  static const _notificationSlideIndex = 5;

  @override
  void dispose() {
    _pageController.dispose();
    _cityController.dispose();
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
          final veryCompact = constraints.maxHeight < 640;
          final heroHeight = veryCompact
              ? 168.0
              : compact
              ? 204.0
              : 260.0;
          final paddingH = constraints.maxWidth < 380
              ? 20.0
              : compact
              ? 22.0
              : 28.0;
          final paddingV = veryCompact
              ? 12.0
              : compact
              ? 18.0
              : 28.0;
          final headerGap = veryCompact
              ? 14.0
              : compact
              ? 22.0
              : 32.0;
          final slideGap = veryCompact
              ? 14.0
              : compact
              ? 20.0
              : 28.0;
          final indicatorTopGap = veryCompact
              ? 12.0
              : compact
              ? 16.0
              : 24.0;
          final actionTopGap = veryCompact
              ? 14.0
              : compact
              ? 20.0
              : 28.0;
          final actionHeight = veryCompact ? 50.0 : 54.0;

          return AnimatedContainer(
            duration: const Duration(milliseconds: 400),
            curve: Curves.easeOutCubic,
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: const [
                  Color(0xFF030510),
                  Color(0xFF070B1D),
                  Color(0xFF120D2A),
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
                  veryCompact
                      ? 14
                      : compact
                      ? 22
                      : 32,
                ),
                child: Column(
                  children: [
                    _OnboardingHeader(onSkip: _isFinishing ? null : _finish),
                    SizedBox(height: headerGap),
                    _OnboardingHero(
                      slide: slide,
                      height: heroHeight,
                      compact: compact,
                      slideIndex: _currentIndex,
                    ),
                    SizedBox(height: slideGap),
                    Expanded(
                      child: PageView.builder(
                        controller: _pageController,
                        itemCount: _slides.length,
                        onPageChanged: (index) {
                          setState(() => _currentIndex = index);
                        },
                        itemBuilder: (context, index) {
                          if (index == _categorySlideIndex) {
                            return _CategoryPreferenceSlide(
                              selectedCategoryIds: _selectedCategoryIds,
                              onToggle: _toggleCategory,
                              compact: compact,
                            );
                          }
                          if (index == _notificationSlideIndex) {
                            return _NotificationPreferenceSlide(
                              cityController: _cityController,
                              marketingOptIn: _marketingOptIn,
                              promotionalPushEnabled: _promotionalPushEnabled,
                              onMarketingChanged: (value) =>
                                  setState(() => _marketingOptIn = value),
                              onPushChanged: (value) => setState(
                                () => _promotionalPushEnabled = value,
                              ),
                              compact: compact,
                            );
                          }
                          return _OnboardingSlide(
                            item: _slides[index],
                            compact: compact,
                            veryCompact: veryCompact,
                          );
                        },
                      ),
                    ),
                    SizedBox(height: indicatorTopGap),
                    _PageIndicator(
                      count: _slides.length,
                      current: _currentIndex,
                      accent: accent,
                      palette: palette,
                    ),
                    SizedBox(height: actionTopGap),
                    DecoratedBox(
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(
                          VennuzoTheme.radiusMd,
                        ),
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
                          minimumSize: Size(double.infinity, actionHeight),
                          backgroundColor: Colors.transparent,
                          foregroundColor: Colors.white,
                          shadowColor: Colors.transparent,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(
                              VennuzoTheme.radiusMd,
                            ),
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
                              ? 'Save preferences'
                              : 'Continue',
                        ),
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
      duration: const Duration(milliseconds: 320),
      curve: Curves.easeOutCubic,
    );
  }

  Future<void> _finish() async {
    if (_isFinishing) return;
    setState(() => _isFinishing = true);
    await widget.onFinished(
      VennuzoOnboardingPreferences(
        categoryIds: _selectedCategoryIds.toList()..sort(),
        city: _cityController.text.trim().isEmpty
            ? 'Accra'
            : _cityController.text.trim(),
        marketingOptIn: _marketingOptIn,
        // Don't persist promo push when marketing is opted out — the switch is
        // disabled in that case, so saving its stale value would contradict the
        // user's visible choice.
        promotionalPushEnabled: _marketingOptIn && _promotionalPushEnabled,
      ),
    );
    if (mounted) setState(() => _isFinishing = false);
  }

  void _toggleCategory(String categoryId) {
    setState(() {
      if (_selectedCategoryIds.contains(categoryId)) {
        _selectedCategoryIds.remove(categoryId);
      } else {
        _selectedCategoryIds.add(categoryId);
      }
    });
  }
}

class _OnboardingHeader extends StatelessWidget {
  const _OnboardingHeader({this.onSkip});

  final VoidCallback? onSkip;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Container(
          padding: const EdgeInsets.fromLTRB(12, 7, 16, 7),
          decoration: BoxDecoration(
            color: VennuzoTheme.surfaceElevated.withValues(alpha: 0.84),
            borderRadius: BorderRadius.circular(VennuzoTheme.radiusFull),
            border: Border.all(color: VennuzoTheme.borderBright),
            boxShadow: VennuzoTheme.shadowElevated,
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              SizedBox(
                width: 24,
                height: 32,
                child: Image.asset(
                  'assets/logo-transparent.png',
                  fit: BoxFit.contain,
                  gaplessPlayback: true,
                ),
              ),
              const SizedBox(width: 8),
              Text(
                'Vennuzo',
                style: Theme.of(context).textTheme.titleMedium?.copyWith(
                  color: VennuzoTheme.textPrimary,
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
                color: VennuzoTheme.textSecondary,
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

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final accent = slide.resolveAccent(palette);

    return AnimatedContainer(
      duration: const Duration(milliseconds: 400),
      curve: Curves.easeOutCubic,
      height: height,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(VennuzoTheme.radiusXl),
        boxShadow: [
          BoxShadow(
            color: accent.withValues(alpha: 0.24),
            blurRadius: 34,
            offset: const Offset(0, 16),
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
            Image.asset(
              slide.imagePath,
              fit: BoxFit.cover,
              alignment: Alignment.center,
              gaplessPlayback: true,
            ),
            DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [
                    Colors.black.withValues(alpha: 0.08),
                    Colors.black.withValues(alpha: 0.18),
                    Colors.black.withValues(alpha: 0.58),
                  ],
                  stops: const [0.0, 0.46, 1.0],
                ),
              ),
            ),
            Positioned(
              top: 16,
              left: 16,
              child: DecoratedBox(
                decoration: BoxDecoration(
                  color: const Color(0xFF080C1D).withValues(alpha: 0.82),
                  borderRadius: BorderRadius.circular(VennuzoTheme.radiusFull),
                  border: Border.all(
                    color: VennuzoTheme.primaryStart.withValues(alpha: 0.28),
                  ),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.12),
                      blurRadius: 14,
                      offset: const Offset(0, 6),
                    ),
                  ],
                ),
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(10, 6, 13, 6),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      SizedBox(
                        width: 18,
                        height: 24,
                        child: Image.asset(
                          'assets/logo-transparent.png',
                          fit: BoxFit.contain,
                          gaplessPlayback: true,
                        ),
                      ),
                      const SizedBox(width: 7),
                      Text(
                        'Vennuzo',
                        style: context.text.labelMedium?.copyWith(
                          color: VennuzoTheme.textPrimary,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
            Positioned(
              left: 18,
              right: 18,
              bottom: 18,
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Container(
                    width: compact ? 50 : 58,
                    height: compact ? 50 : 58,
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.20),
                      borderRadius: BorderRadius.circular(18),
                      border: Border.all(
                        color: Colors.white.withValues(alpha: 0.36),
                      ),
                    ),
                    child: Icon(
                      slide.icon,
                      size: compact ? 26 : 30,
                      color: Colors.white,
                    ),
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          slide.badge,
                          style: context.text.titleMedium?.copyWith(
                            color: Colors.white,
                            fontWeight: FontWeight.w800,
                            shadows: [
                              Shadow(
                                color: Colors.black.withValues(alpha: 0.35),
                                blurRadius: 12,
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          slide.caption,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: context.text.bodyMedium?.copyWith(
                            color: Colors.white.withValues(alpha: 0.88),
                            height: 1.25,
                          ),
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
      children: List.generate(count, (index) {
        final isActive = index == current;
        return AnimatedContainer(
          duration: const Duration(milliseconds: 300),
          curve: Curves.easeOutCubic,
          margin: EdgeInsets.only(right: index == count - 1 ? 0 : 10),
          width: isActive ? 32 : 8,
          height: 8,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(VennuzoTheme.radiusFull),
            color: isActive ? accent : palette.ink.withValues(alpha: 0.14),
          ),
        );
      }),
    );
  }
}

class _OnboardingSlide extends StatelessWidget {
  const _OnboardingSlide({
    required this.item,
    required this.compact,
    required this.veryCompact,
  });

  final _OnboardingSlideData item;
  final bool compact;
  final bool veryCompact;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final accent = item.resolveAccent(palette);

    return SingleChildScrollView(
      padding: EdgeInsets.fromLTRB(compact ? 4 : 10, 0, compact ? 4 : 10, 6),
      physics: const BouncingScrollPhysics(),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            item.title,
            style:
                (compact
                        ? Theme.of(context).textTheme.titleLarge?.copyWith(
                            fontSize: veryCompact ? 20 : 22,
                            height: 1.2,
                          )
                        : Theme.of(context).textTheme.headlineSmall)
                    ?.copyWith(
                      fontWeight: FontWeight.w800,
                      color: VennuzoTheme.textPrimary,
                    ),
          ),
          SizedBox(
            height: veryCompact
                ? 8
                : compact
                ? 12
                : 16,
          ),
          Text(
            item.body,
            style: Theme.of(context).textTheme.bodyLarge?.copyWith(
              color: VennuzoTheme.textSecondary,
              height: veryCompact ? 1.38 : 1.5,
              fontSize: veryCompact
                  ? 14
                  : compact
                  ? 15
                  : 16,
            ),
          ),
          SizedBox(
            height: veryCompact
                ? 12
                : compact
                ? 18
                : 24,
          ),
          Container(
            width: double.infinity,
            padding: EdgeInsets.all(
              veryCompact
                  ? 14
                  : compact
                  ? 18
                  : 22,
            ),
            decoration: BoxDecoration(
              color: VennuzoTheme.surfaceElevated,
              borderRadius: BorderRadius.circular(VennuzoTheme.radiusLg),
              border: Border.all(
                color: accent.withValues(alpha: 0.32),
                width: 1,
              ),
              boxShadow: VennuzoTheme.shadowResting,
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
                          color: VennuzoTheme.textSecondary,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      const SizedBox(height: 6),
                      Text(
                        item.statValue,
                        style: Theme.of(context).textTheme.titleLarge?.copyWith(
                          fontSize: compact ? 18 : 20,
                          fontWeight: FontWeight.w800,
                          color: VennuzoTheme.textPrimary,
                        ),
                      ),
                    ],
                  ),
                ),
                Container(
                  width: veryCompact ? 44 : 50,
                  height: veryCompact ? 44 : 50,
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(15),
                    gradient: LinearGradient(
                      colors: [
                        accent.withValues(alpha: 0.95),
                        Color.lerp(accent, Colors.black, 0.18)!,
                      ],
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                    ),
                    boxShadow: [
                      BoxShadow(
                        color: accent.withValues(alpha: 0.20),
                        blurRadius: 16,
                        offset: const Offset(0, 6),
                      ),
                    ],
                  ),
                  child: Icon(
                    item.icon,
                    size: veryCompact ? 22 : 25,
                    color: Colors.white,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _CategoryPreferenceSlide extends StatelessWidget {
  const _CategoryPreferenceSlide({
    required this.selectedCategoryIds,
    required this.onToggle,
    required this.compact,
  });

  final Set<String> selectedCategoryIds;
  final void Function(String categoryId) onToggle;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: EdgeInsets.fromLTRB(compact ? 2 : 8, 0, compact ? 2 : 8, 6),
      physics: const BouncingScrollPhysics(),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Pick the event categories you want Vennuzo to prioritize.',
            style: context.text.titleMedium?.copyWith(
              color: VennuzoTheme.textPrimary,
              fontWeight: FontWeight.w800,
              height: 1.2,
            ),
          ),
          const SizedBox(height: 10),
          Text(
            selectedCategoryIds.isEmpty
                ? 'Choose none for a broad feed across every event type.'
                : '${selectedCategoryIds.length} selected',
            style: context.text.bodyMedium?.copyWith(
              color: VennuzoTheme.textSecondary,
            ),
          ),
          const SizedBox(height: 16),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: EventTaxonomy.categories.map((category) {
              final selected = selectedCategoryIds.contains(category.id);
              return _PreferenceChip(
                category: category,
                selected: selected,
                onTap: () => onToggle(category.id),
              );
            }).toList(),
          ),
        ],
      ),
    );
  }
}

class _NotificationPreferenceSlide extends StatelessWidget {
  const _NotificationPreferenceSlide({
    required this.cityController,
    required this.marketingOptIn,
    required this.promotionalPushEnabled,
    required this.onMarketingChanged,
    required this.onPushChanged,
    required this.compact,
  });

  final TextEditingController cityController;
  final bool marketingOptIn;
  final bool promotionalPushEnabled;
  final ValueChanged<bool> onMarketingChanged;
  final ValueChanged<bool> onPushChanged;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: EdgeInsets.fromLTRB(compact ? 2 : 8, 0, compact ? 2 : 8, 6),
      physics: const BouncingScrollPhysics(),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Set your default city and promo rules.',
            style: context.text.titleMedium?.copyWith(
              color: VennuzoTheme.textPrimary,
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(height: 14),
          TextField(
            controller: cityController,
            textCapitalization: TextCapitalization.words,
            decoration: const InputDecoration(
              labelText: 'Primary city',
              hintText: 'Accra',
            ),
          ),
          const SizedBox(height: 14),
          SwitchListTile.adaptive(
            contentPadding: EdgeInsets.zero,
            value: marketingOptIn,
            onChanged: onMarketingChanged,
            title: const Text('Allow promotional campaigns'),
            subtitle: const Text(
              'Only for matching categories, creator audiences, and opted-in lists.',
            ),
          ),
          SwitchListTile.adaptive(
            contentPadding: EdgeInsets.zero,
            value: promotionalPushEnabled,
            onChanged: marketingOptIn ? onPushChanged : null,
            title: const Text('Allow promotional push alerts'),
            subtitle: const Text(
              'Push campaigns stay filtered by your event preferences.',
            ),
          ),
        ],
      ),
    );
  }
}

class _PreferenceChip extends StatelessWidget {
  const _PreferenceChip({
    required this.category,
    required this.selected,
    required this.onTap,
  });

  final VennuzoEventCategory category;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return FilterChip(
      selected: selected,
      onSelected: (_) => onTap(),
      showCheckmark: false,
      avatar: Icon(category.icon, size: 18),
      label: Text(category.shortLabel),
      labelStyle: context.text.labelMedium?.copyWith(
        color: selected ? Colors.white : VennuzoTheme.textPrimary,
        fontWeight: FontWeight.w800,
      ),
      selectedColor: VennuzoTheme.primaryStart,
      backgroundColor: VennuzoTheme.surfaceElevated,
      side: BorderSide(
        color: selected ? VennuzoTheme.primaryStart : VennuzoTheme.borderBright,
      ),
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
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
    required this.imagePath,
    required this.caption,
    required this.accent,
    required this.icon,
  });

  final String badge;
  final String title;
  final String body;
  final String statLabel;
  final String statValue;
  final String imagePath;
  final String caption;
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
