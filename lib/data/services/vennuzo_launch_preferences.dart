import 'package:shared_preferences/shared_preferences.dart';

class VennuzoOnboardingPreferences {
  const VennuzoOnboardingPreferences({
    this.categoryIds = const <String>[],
    this.city = 'Accra',
    this.marketingOptIn = false,
    this.promotionalPushEnabled = true,
  });

  final List<String> categoryIds;
  final String city;
  final bool marketingOptIn;
  final bool promotionalPushEnabled;

  bool get hasCategoryPreferences => categoryIds.isNotEmpty;

  VennuzoOnboardingPreferences copyWith({
    List<String>? categoryIds,
    String? city,
    bool? marketingOptIn,
    bool? promotionalPushEnabled,
  }) {
    return VennuzoOnboardingPreferences(
      categoryIds: categoryIds ?? this.categoryIds,
      city: city ?? this.city,
      marketingOptIn: marketingOptIn ?? this.marketingOptIn,
      promotionalPushEnabled:
          promotionalPushEnabled ?? this.promotionalPushEnabled,
    );
  }
}

class VennuzoLaunchPreferences {
  VennuzoLaunchPreferences._();

  static const _onboardingCompletedKey = 'vennuzo.onboarding.completed.v2';
  static const _onboardingCategoryIdsKey = 'vennuzo.onboarding.category_ids.v1';
  static const _onboardingCityKey = 'vennuzo.onboarding.city.v1';
  static const _onboardingMarketingOptInKey =
      'vennuzo.onboarding.marketing_opt_in.v1';
  static const _onboardingPromoPushKey =
      'vennuzo.onboarding.promotional_push.v1';
  static const _onboardingSyncedUidKey = 'vennuzo.onboarding.synced_uid.v1';
  static const _discoverVisitedKey = 'vennuzo.discover.visited';
  static const _announcementSeenPrefix = 'vennuzo.announcement.seen.';

  static Future<bool> shouldShowOnboarding() async {
    final prefs = await SharedPreferences.getInstance();
    return !(prefs.getBool(_onboardingCompletedKey) ?? false);
  }

  static Future<void> markOnboardingCompleted() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_onboardingCompletedKey, true);
  }

  static Future<void> saveOnboardingPreferences(
    VennuzoOnboardingPreferences preferences,
  ) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setStringList(
      _onboardingCategoryIdsKey,
      preferences.categoryIds,
    );
    await prefs.setString(_onboardingCityKey, preferences.city.trim());
    await prefs.setBool(
      _onboardingMarketingOptInKey,
      preferences.marketingOptIn,
    );
    await prefs.setBool(
      _onboardingPromoPushKey,
      preferences.promotionalPushEnabled,
    );
  }

  static Future<VennuzoOnboardingPreferences>
  loadOnboardingPreferences() async {
    final prefs = await SharedPreferences.getInstance();
    return VennuzoOnboardingPreferences(
      categoryIds:
          prefs.getStringList(_onboardingCategoryIdsKey) ?? const <String>[],
      city: prefs.getString(_onboardingCityKey) ?? 'Accra',
      marketingOptIn: prefs.getBool(_onboardingMarketingOptInKey) ?? false,
      promotionalPushEnabled: prefs.getBool(_onboardingPromoPushKey) ?? true,
    );
  }

  static Future<bool> shouldSyncOnboardingPreferencesFor(String uid) async {
    if (uid.trim().isEmpty) return false;
    final prefs = await SharedPreferences.getInstance();
    final local = await loadOnboardingPreferences();
    if (!local.hasCategoryPreferences && !local.marketingOptIn) return false;
    return prefs.getString(_onboardingSyncedUidKey) != uid;
  }

  static Future<void> markOnboardingPreferencesSynced(String uid) async {
    if (uid.trim().isEmpty) return;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_onboardingSyncedUidKey, uid);
  }

  static Future<bool> shouldAllowAnnouncementTakeover() async {
    final prefs = await SharedPreferences.getInstance();
    final onboardingCompleted = prefs.getBool(_onboardingCompletedKey) ?? false;
    final hasVisitedDiscover = prefs.getBool(_discoverVisitedKey) ?? false;

    if (!hasVisitedDiscover) {
      await prefs.setBool(_discoverVisitedKey, true);
    }

    return onboardingCompleted && hasVisitedDiscover;
  }

  static Future<bool> hasSeenAnnouncementTakeover(String campaignId) async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool('$_announcementSeenPrefix$campaignId') ?? false;
  }

  static Future<void> markAnnouncementTakeoverSeen(String campaignId) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('$_announcementSeenPrefix$campaignId', true);
  }
}
