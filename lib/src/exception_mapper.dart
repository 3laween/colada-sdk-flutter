/// Translates platform-channel failures into typed Colada exceptions.
library;

import 'package:flutter/services.dart';

import 'error_codes.dart';
import 'exceptions.dart';

/// Converts a [PlatformException] raised by a native bridge into the matching
/// [ColadaException].
///
/// [method] is the facade method that was called, used when the code carries no
/// better context.
///
/// An unrecognised code is **not** an error: it degrades to
/// [ColadaNetworkException] carrying the original message, so a native bridge
/// that reports something this Dart version has not heard of still surfaces as
/// a Colada exception rather than leaking a raw [PlatformException] to the app.
/// That is the whole promise of the sealed hierarchy — one `catch` clause.
ColadaException mapPlatformException(String method, PlatformException error) {
  final details = error.details;
  final map = details is Map
      ? <String, Object?>{
          for (final MapEntry<Object?, Object?> e in details.entries)
            '${e.key}': e.value,
        }
      : const <String, Object?>{};

  switch (error.code) {
    case ColadaErrorCode.notInitialized:
      return ColadaNotInitializedException(method);

    case ColadaErrorCode.invalidConfig:
      return ColadaInvalidConfigException(
        map['fieldName'] as String? ?? 'config',
        error.message ?? 'was rejected by the native SDK.',
      );

    case ColadaErrorCode.invalidEvent:
      return ColadaInvalidEventException(
        map['eventName'] as String? ?? 'event',
        error.message ?? 'was rejected by the native SDK.',
      );

    case ColadaErrorCode.missingUser:
      return const ColadaMissingUserException();

    case ColadaErrorCode.backendRejected:
      return ColadaBackendRejectedException(
        (map['statusCode'] as num?)?.toInt() ?? 0,
        map['serverMessage'] as String? ?? error.message,
      );

    case ColadaErrorCode.deliveryFailed:
      return ColadaDeliveryFailedException(
        (map['attempts'] as num?)?.toInt() ?? 0,
      );

    case ColadaErrorCode.network:
      return ColadaNetworkException(error.message);

    case ColadaErrorCode.tokenExpired:
      return const ColadaTokenExpiredException();

    case ColadaErrorCode.deviceIdentityUnavailable:
      return const ColadaDeviceIdentityUnavailableException();

    case ColadaErrorCode.trackingBlocked:
      return const ColadaTrackingBlockedException();

    case ColadaErrorCode.unsupported:
      return ColadaUnsupportedException(
        feature: map['feature'] as String? ?? method,
        platform: map['platform'] as String? ?? 'this platform',
        alternative: map['alternative'] as String?,
      );

    default:
      // Unknown code. Still a ColadaException — never a raw PlatformException.
      return ColadaNetworkException(
        '${error.code}${error.message == null ? '' : ': ${error.message}'}',
      );
  }
}

/// Converts a [MissingPluginException] into a typed exception.
///
/// This is what an app sees when it calls the SDK on a platform the plugin does
/// not implement — web, macOS, Windows, Linux — or before the native side is
/// registered. Reporting it as "unsupported" rather than a network failure
/// stops people debugging connectivity that was never involved.
ColadaException mapMissingPlugin(String method) => ColadaUnsupportedException(
      feature: 'Colada.$method',
      platform: 'this platform',
      alternative: 'The Colada SDK supports Android and iOS only.',
    );
