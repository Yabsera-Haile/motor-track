/// Backend settings, passed at build time:
///   flutter run --dart-define-from-file=env/local.json
/// See env/example.json. The publishable key is designed to ship inside apps; the
/// database only answers phones that joined with the team code.
abstract final class Config {
  static const supabaseUrl = String.fromEnvironment('SUPABASE_URL');
  static const supabasePublishableKey = String.fromEnvironment('SUPABASE_PUBLISHABLE_KEY');

  static bool get isConfigured => supabaseUrl.isNotEmpty && supabasePublishableKey.isNotEmpty;
}
