/// Build-time switches for the Supabase -> AWS backend migration.
///
/// `USE_AWS_AUTH` defaults to ON: the screens already migrated (profile, dashboard,
/// notifications, announcements, events, FAQs, surveys) read from the AWS API and
/// need an AWS session. Pass `--dart-define=USE_AWS_AUTH=false` only to exercise the
/// legacy Supabase login path for screens that have not been migrated yet.
/// The flag is removed once the whole app is on the AWS backend.
class FeatureFlags {
  FeatureFlags._();

  /// Use the AWS backend (`/auth/login`) for sign-in instead of Supabase Auth.
  static const bool useAwsAuth = bool.fromEnvironment('USE_AWS_AUTH', defaultValue: true);
}
