/// The error-code vocabulary shared by Dart, Kotlin and Swift.
///
/// A native bridge reports a failure by completing its Pigeon callback with an
/// error whose *code* is one of these strings. The Dart side maps the code back
/// to a typed [ColadaException] — see `exception_mapper.dart`.
///
/// ⚠️ **These strings are a three-language contract.** The Kotlin and Swift
/// bridges declare matching constants (`ColadaErrorCode` in each), and
/// `error_codes_test.dart` asserts this list is complete. Changing a value here
/// without changing both native constants silently turns a typed exception into
/// a generic one — the failure still surfaces, but loses its type, which is the
/// whole point of the hierarchy.
library;

/// Codes a native bridge may report.
abstract final class ColadaErrorCode {
  /// A method was called before the native SDK finished starting.
  static const String notInitialized = 'colada/not-initialized';

  /// The configuration was rejected by the native SDK.
  ///
  /// Rare: Dart validates the config before it crosses. Reaching this means
  /// the Dart and native validators disagree, which is a bug worth surfacing.
  static const String invalidConfig = 'colada/invalid-config';

  /// The event was rejected by the native SDK.
  ///
  /// Rare, for the same reason as [invalidConfig].
  static const String invalidEvent = 'colada/invalid-event';

  /// An event was tracked before the user was identified. iOS only.
  static const String missingUser = 'colada/missing-user';

  /// The backend rejected the request and retrying cannot help.
  ///
  /// `details` carries `{'statusCode': int, 'serverMessage': String?}`.
  static const String backendRejected = 'colada/backend-rejected';

  /// Delivery was attempted, retried, and failed every time.
  ///
  /// `details` carries `{'attempts': int}`.
  static const String deliveryFailed = 'colada/delivery-failed';

  /// The request could not reach the backend at all.
  static const String network = 'colada/network';

  /// The session token expired and could not be renewed.
  static const String tokenExpired = 'colada/token-expired';

  /// The device identity could not be read from secure storage. iOS only.
  static const String deviceIdentityUnavailable =
      'colada/device-identity-unavailable';

  /// The OS blocked the request on privacy grounds. iOS only.
  static const String trackingBlocked = 'colada/tracking-blocked';

  /// The capability does not exist on this platform.
  ///
  /// `details` carries `{'feature': String, 'platform': String}`.
  static const String unsupported = 'colada/unsupported';

  /// Every code, for exhaustiveness checks in tests.
  static const List<String> values = <String>[
    notInitialized,
    invalidConfig,
    invalidEvent,
    missingUser,
    backendRejected,
    deliveryFailed,
    network,
    tokenExpired,
    deviceIdentityUnavailable,
    trackingBlocked,
    unsupported,
  ];
}
