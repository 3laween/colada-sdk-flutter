/// Every failure the Colada SDK can report.
///
/// The native Android SDK never throws — it degrades to a no-op — while the
/// native iOS SDK throws a typed error. This package unifies the two behind one
/// sealed hierarchy, so a Flutter integrator writes one `catch` and gets the
/// same categories on both platforms.
///
/// Because [ColadaException] is `sealed`, a `switch` over it is checked by the
/// compiler: adding a case in a future version breaks an exhaustive switch at
/// compile time rather than silently falling through at runtime.
///
/// ```dart
/// try {
///   await Colada.track(const Purchase(amount: 49.99, currency: 'SAR', orderId: 'ORD-1'));
/// } on ColadaMissingUserException {
///   // iOS only: setUser() has not been called yet.
/// } on ColadaException catch (e) {
///   log('Colada: ${e.message}');
/// }
/// ```
library;

import 'package:meta/meta.dart';

/// Base type for every error reported by the Colada SDK.
@immutable
sealed class ColadaException implements Exception {
  /// Creates an exception carrying a human-readable [message].
  const ColadaException(this.message);

  /// What went wrong, phrased so the fix is obvious from the message alone.
  final String message;

  @override
  String toString() => '$runtimeType: $message';
}

/// A method was called before `Colada.initialize` completed.
///
/// Every call except `initialize` itself requires a started SDK. Initialize
/// once, as early as possible — ideally the first statement in `main()`, before
/// `runApp`.
final class ColadaNotInitializedException extends ColadaException {
  /// Creates the exception for the method named [method].
  const ColadaNotInitializedException(this.method)
      : super('Colada.$method was called before initialize() completed. '
            'Call Colada.initialize() first, as early as possible in main().');

  /// Name of the method that was called too early.
  final String method;
}

/// The configuration passed to `initialize` cannot be used.
///
/// Raised entirely on the Dart side, before anything crosses to the native
/// SDK, so an invalid key fails identically on Android and iOS.
final class ColadaInvalidConfigException extends ColadaException {
  /// Creates the exception for [fieldName], describing the problem in [message].
  const ColadaInvalidConfigException(this.fieldName, String message)
      : super('ColadaConfig.$fieldName $message');

  /// The `ColadaConfig` property at fault, e.g. `publicTenantKey`.
  final String fieldName;
}

/// An event could not be built or is missing a required field.
///
/// Raised on the Dart side before the event crosses to the native SDK, so a
/// malformed event fails the same way on both platforms rather than being
/// rejected by one native SDK and silently accepted by the other.
final class ColadaInvalidEventException extends ColadaException {
  /// Creates the exception for the event named [eventName].
  const ColadaInvalidEventException(this.eventName, String message)
      : super('$eventName $message');

  /// Wire name of the offending event, e.g. `Purchase`.
  final String eventName;
}

/// An event was tracked before the user was identified.
///
/// **iOS only.** The native iOS SDK requires `externalUserId` on every event
/// and rejects the call outright. The native Android SDK instead holds the
/// event durably and releases it on the next `setUser`/`clearUser`, so this is
/// never raised there.
///
/// Call `Colada.setUser()` after sign-up, after login, **and** on app start
/// when restoring a saved session — then track.
final class ColadaMissingUserException extends ColadaException {
  /// Creates the exception.
  const ColadaMissingUserException()
      : super('An event was tracked before Colada.setUser() was called. On iOS '
            'the event is rejected; on Android it would have been held and sent '
            'once a user became known. Call setUser() first.');
}

/// The backend rejected the request and retrying cannot help.
///
/// A client-side problem — a revoked key, a user the backend has never seen, a
/// malformed field — not a transient delivery failure. Contrast
/// [ColadaDeliveryFailedException].
final class ColadaBackendRejectedException extends ColadaException {
  /// Creates the exception for HTTP [statusCode], with the server's own
  /// [serverMessage] when it supplied one.
  const ColadaBackendRejectedException(this.statusCode, [this.serverMessage])
      : super('The Colada backend rejected the request with HTTP $statusCode'
            '${serverMessage == null ? '.' : ': $serverMessage'}');

  /// HTTP status returned by the backend, e.g. `400`, `401`, `404`.
  final int statusCode;

  /// The backend's own error message, when it supplied one.
  final String? serverMessage;
}

/// Delivery was attempted and retried, and every attempt failed.
///
/// Transient by nature. On both platforms the event is queued and retried
/// later; this exception reports that the *immediate* attempts did not succeed,
/// not that the event is lost.
final class ColadaDeliveryFailedException extends ColadaException {
  /// Creates the exception after [attempts] failed delivery attempts.
  const ColadaDeliveryFailedException(this.attempts)
      : super('Delivery failed after $attempts attempt(s). The event remains '
            'queued and will be retried.');

  /// How many delivery attempts were made before giving up for now.
  final int attempts;
}

/// The request could not reach the backend at all.
///
/// No HTTP status was received — the device is offline, the request was
/// cancelled, or the connection dropped.
final class ColadaNetworkException extends ColadaException {
  /// Creates the exception, optionally describing the underlying cause.
  const ColadaNetworkException([String? detail])
      : super('The request could not reach the Colada backend'
            '${detail == null ? '.' : ': $detail'}');
}

/// The SDK session token expired and could not be renewed.
///
/// The SDK refreshes its own token automatically, so reaching this means
/// automatic recovery was already exhausted. Realistic causes are a device
/// clock far enough off that a fresh token reads as already expired, or a
/// tenant key revoked mid-session. Calling `initialize` again does not help.
final class ColadaTokenExpiredException extends ColadaException {
  /// Creates the exception.
  const ColadaTokenExpiredException()
      : super('The Colada session token expired and re-minting it did not '
            'help. Check the device clock and whether the tenant key is still '
            'valid.');
}

/// The device identity could not be read from secure storage.
///
/// **iOS only.** A genuine storage failure — typically the device rebooted and
/// is still locked, so the Keychain is unreadable. Nothing was minted and no
/// state changed; initializing again later retries the read.
final class ColadaDeviceIdentityUnavailableException extends ColadaException {
  /// Creates the exception.
  const ColadaDeviceIdentityUnavailableException()
      : super('The device identity could not be read from the Keychain. This '
            'is usually a locked device after a reboot — retry later.');
}

/// The OS blocked the request on privacy grounds.
///
/// **iOS only.** The backend host is declared in the SDK's privacy manifest as
/// a tracking domain, and App Tracking Transparency has not been authorised.
/// Nothing was sent, and retrying cannot help until ATT is granted.
///
/// The OS surfaces this as an offline error, which is misleading — the network
/// is fine. It has its own case so nobody goes hunting for a connectivity bug
/// that does not exist.
final class ColadaTrackingBlockedException extends ColadaException {
  /// Creates the exception.
  const ColadaTrackingBlockedException()
      : super('The request was blocked by iOS tracking prevention. The network '
            'is fine — App Tracking Transparency has not been authorised.');
}

/// The requested capability does not exist on this platform.
///
/// The native Android and iOS SDKs are not perfectly parallel. Where a
/// capability exists on one and is silently wrong to skip on the other, this is
/// thrown rather than no-oped. Capabilities that are merely *unavailable* — and
/// harmless to skip — emit a warning on the log stream instead, unless
/// `ColadaConfig.strictMode` is on, which promotes those warnings to this
/// exception.
///
/// See `doc/PLATFORM_DIFFERENCES.md` for the full list.
final class ColadaUnsupportedException extends ColadaException {
  /// Creates the exception for [feature], unsupported on [platform].
  const ColadaUnsupportedException({
    required this.feature,
    required this.platform,
    String? alternative,
  }) : super('$feature is not supported on $platform.'
            '${alternative == null ? '' : ' $alternative'}');

  /// The capability that is unavailable, e.g. `Custom event names`.
  final String feature;

  /// Platform on which it is unavailable, e.g. `iOS`.
  final String platform;
}
