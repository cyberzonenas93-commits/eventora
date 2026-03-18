import 'package:shared_preferences/shared_preferences.dart';

class EventoraLaunchPreferences {
  EventoraLaunchPreferences._();

  static const _onboardingCompletedKey = 'eventora.onboarding.completed';
  static const _discoverVisitedKey = 'eventora.discover.visited';

  static Future<bool> shouldShowOnboarding() async {
    final prefs = await SharedPreferences.getInstance();
    return !(prefs.getBool(_onboardingCompletedKey) ?? false);
  }

  static Future<void> markOnboardingCompleted() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_onboardingCompletedKey, true);
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
}
