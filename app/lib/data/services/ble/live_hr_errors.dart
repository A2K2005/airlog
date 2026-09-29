// Every Bluetooth failure leaves the live-HR services as a typed
// LiveHrException (domain/repositories.dart), so the UI never parses
// plugin messages. The original text is kept as the message.

import 'package:flutter/services.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart' as fbp;

import '../../../domain/repositories.dart';

/// Maps [e] to a [LiveHrException]. [fallback] is the kind when nothing
/// more specific is recognisable (e.g. connectFailed while connecting).
LiveHrException liveHrErrorFrom(
  Object e, {
  LiveHrErrorKind fallback = LiveHrErrorKind.unknown,
}) {
  if (e is LiveHrException) return e;
  final text = '$e';
  if (e is fbp.FlutterBluePlusException &&
      e.platform == fbp.ErrorPlatform.fbp) {
    final code = e.code;
    final kind =
        code == null || code < 0 || code >= fbp.FbpErrorCode.values.length
        ? null
        : switch (fbp.FbpErrorCode.values[code]) {
            fbp.FbpErrorCode.adapterIsOff ||
            fbp.FbpErrorCode.userRejected => LiveHrErrorKind.bluetoothOff,
            fbp.FbpErrorCode.deviceIsDisconnected ||
            fbp.FbpErrorCode.connectionCanceled => LiveHrErrorKind.linkLost,
            fbp.FbpErrorCode.serviceNotFound ||
            fbp.FbpErrorCode.characteristicNotFound =>
              LiveHrErrorKind.noHeartRateService,
            fbp.FbpErrorCode.androidOnly ||
            fbp.FbpErrorCode.applePlatformOnly => LiveHrErrorKind.unsupported,
            _ => null,
          };
    if (kind != null) return LiveHrException(kind, text);
  }
  if (e is MissingPluginException || e is UnimplementedError) {
    return LiveHrException(LiveHrErrorKind.unsupported, text);
  }
  final s = text.toLowerCase();
  if (s.contains('permission')) {
    return LiveHrException(LiveHrErrorKind.permissionDenied, text);
  }
  // flutter_blue_plus on Android: "Bluetooth must be turned on",
  // "Bluetooth adapter is off".
  if (s.contains('must be turned on') ||
      s.contains('adapter is off') ||
      s.contains('bluetooth is off') ||
      s.contains('turned off')) {
    return LiveHrException(LiveHrErrorKind.bluetoothOff, text);
  }
  if (s.contains('not supported') || s.contains('unsupported')) {
    return LiveHrException(LiveHrErrorKind.unsupported, text);
  }
  return LiveHrException(fallback, text);
}
