// Small injectable platform seams shared by several features (Strain,
// Trends, Live, Settings, Diagnostics, Onboarding, Methodology):
//
//   * fileSharerProvider   share_plus behind an interface (tests record calls)
//   * linkOpenerProvider   url_launcher behind a function
//   * noRetry              Riverpod retry policy for one-shot platform work
//
// The wall clock is NOT here: every screen reads `clockProvider`
// (app/providers.dart), the one clock tests and goldens pin.
//
// Shared kit for features/: imports no feature (features never import each
// other; shared pieces live in app/ or design/).

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:share_plus/share_plus.dart';
import 'package:url_launcher/url_launcher.dart';

/// Hands files to the system share sheet.
abstract class FileSharer {
  Future<void> share(List<String> paths, {String? subject, String? text});
}

class PlatformFileSharer implements FileSharer {
  const PlatformFileSharer();

  @override
  Future<void> share(
    List<String> paths, {
    String? subject,
    String? text,
  }) async {
    await SharePlus.instance.share(
      ShareParams(
        files: [for (final p in paths) XFile(p)],
        subject: subject,
        text: text,
      ),
    );
  }
}

final fileSharerProvider = Provider<FileSharer>(
  (ref) => const PlatformFileSharer(),
);

/// Opens a link outside the app. Returns false when nothing could open it.
typedef LinkOpener = Future<bool> Function(Uri uri);

final linkOpenerProvider = Provider<LinkOpener>(
  (ref) =>
      (uri) => launchUrl(uri, mode: LaunchMode.externalApplication),
);

/// Riverpod 3 retries a failing provider with backoff by default. A failed
/// Bluetooth scan, permission prompt or file write must not silently re-run,
/// so the view-models opt out.
Duration? noRetry(int retryCount, Object error) => null;
