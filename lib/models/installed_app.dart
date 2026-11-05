/// Installed identity and device compatibility, independent of display version.
class InstalledApp {
  const InstalledApp(
      {required this.version,
      required this.build,
      required this.sdk,
      required this.platform});
  final String version, platform;
  final int build, sdk;
}
