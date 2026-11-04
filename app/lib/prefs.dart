import 'package:shared_preferences/shared_preferences.dart';

/// Small per-phone choices, kept on the phone only.
abstract final class AppPrefs {
  static SharedPreferences? _prefs;

  static Future<void> load() async {
    try {
      _prefs = await SharedPreferences.getInstance();
    } catch (_) {
      // Storage can be unavailable (e.g. some browsers); the app still works, it just asks again.
    }
  }

  /// The intro and permission pages were shown on this phone.
  static bool get onboardingDone => _prefs?.getBool('onboarding_done') ?? false;
  static set onboardingDone(bool v) => _prefs?.setBool('onboarding_done', v);

  /// During the intro, someone said MoMo money arrives on this phone.
  static bool get readerWanted => _prefs?.getBool('reader_wanted') ?? false;
  static set readerWanted(bool v) => _prefs?.setBool('reader_wanted', v);
}
