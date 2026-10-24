/// Build info injected at compile time via `--dart-define`.
///
/// Use `scripts/flutter.sh run` / `scripts/flutter.sh build ...` to fill these
/// from git automatically. Without them, the defaults below are shown.
class AppVersion {
  AppVersion._();

  /// Total commit count on HEAD (`git rev-list --count HEAD`).
  static const String commitCount =
      String.fromEnvironment('GIT_COUNT', defaultValue: '0');

  /// Short commit hash (`git rev-parse --short HEAD`).
  static const String commitSha =
      String.fromEnvironment('GIT_SHA', defaultValue: 'dev');

  /// e.g. "Version 26 (a0276c1)"
  static const String display = 'Version $commitCount ($commitSha)';
}
