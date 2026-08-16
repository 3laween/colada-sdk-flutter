import Flutter
import UIKit

/// Colada Flutter plugin — iOS entry point.
///
/// Phase 4 registers the Pigeon-generated host API and answers every call with
/// `ColadaErrorCode.notInitialized`. The real bridge to the native Colada iOS
/// SDK arrives in Phases 9 to 12, method by method.
///
/// Answering with a proper Colada error rather than leaving the channel
/// unregistered is deliberate: an unregistered channel surfaces in Dart as a
/// `MissingPluginException`, which the Dart layer reports as "this platform is
/// not supported" — actively misleading on iOS. A registered handler that
/// reports "not implemented yet" is the honest answer.
public class ColadaSdkPlugin: NSObject, FlutterPlugin, ColadaHostApi {

  public static func register(with registrar: FlutterPluginRegistrar) {
    let instance = ColadaSdkPlugin()
    // ColadaHostApiSetup, not ColadaHostApi: in Swift, Pigeon generates the API
    // as a protocol and puts setUp on a separate generated class. (Kotlin
    // differs — there setUp lives in the interface's companion object.)
    ColadaHostApiSetup.setUp(binaryMessenger: registrar.messenger(), api: instance)
    // Retained so the instance outlives `register`; also the hook the deep-link
    // callbacks in Phase 12 need.
    registrar.publish(instance)
    // The two event channels (attribution, logs) are registered in Phase 11,
    // together with the native listeners that feed them.
  }

  // MARK: - ColadaHostApi
  //
  // Phase 9 replaces initialize/isInitialized/deviceId, Phase 10 the identity
  // and event calls, Phase 11 attribution, Phase 12 deep links.

  func initialize(config: NativeConfig, completion: @escaping (Result<Void, Error>) -> Void) {
    completion(.failure(Self.notImplemented("initialize")))
  }

  func isInitialized(completion: @escaping (Result<Bool, Error>) -> Void) {
    completion(.failure(Self.notImplemented("isInitialized")))
  }

  func deviceId(completion: @escaping (Result<String?, Error>) -> Void) {
    completion(.failure(Self.notImplemented("deviceId")))
  }

  func setUser(externalUserId: String, completion: @escaping (Result<Void, Error>) -> Void) {
    completion(.failure(Self.notImplemented("setUser")))
  }

  func clearUser(completion: @escaping (Result<Void, Error>) -> Void) {
    completion(.failure(Self.notImplemented("clearUser")))
  }

  func track(
    eventName: String,
    metadata: [String: Any?],
    completion: @escaping (Result<Void, Error>) -> Void
  ) {
    completion(.failure(Self.notImplemented("track")))
  }

  func flush(completion: @escaping (Result<Void, Error>) -> Void) {
    completion(.failure(Self.notImplemented("flush")))
  }

  func currentAttribution(completion: @escaping (Result<NativeAttribution?, Error>) -> Void) {
    completion(.failure(Self.notImplemented("currentAttribution")))
  }

  func consumeDeferredDeepLink(
    completion: @escaping (Result<NativeDeferredDeepLink?, Error>) -> Void
  ) {
    completion(.failure(Self.notImplemented("consumeDeferredDeepLink")))
  }

  func handleDeepLink(url: String, completion: @escaping (Result<Void, Error>) -> Void) {
    completion(.failure(Self.notImplemented("handleDeepLink")))
  }

  // Must be a Pigeon `PigeonError`, not a custom Error type: the generated
  // `wrapError` only forwards code/message/details for PigeonError, and falls
  // back to the type's description for anything else. A custom error here would
  // reach Dart with a code that maps to no typed exception at all.
  private static func notImplemented(_ method: String) -> PigeonError {
    coladaError(
      code: ColadaErrorCode.notInitialized,
      message: "Colada.\(method) is not wired on iOS yet (arrives in Phases 9-12)."
    )
  }
}

/// Error codes reported to Dart.
///
/// ⚠️ These strings are a three-language contract. They must stay identical to
/// `ColadaErrorCode` in `lib/src/error_codes.dart` and to the Kotlin constants
/// in `android/src/main/kotlin/io/coladaapp/sdk/flutter/ColadaSdkPlugin.kt`. A
/// mismatch does not break the call — the failure still reaches the app — but
/// it loses its type, which is the entire point of the exception hierarchy.
enum ColadaErrorCode {
  static let notInitialized = "colada/not-initialized"
  static let invalidConfig = "colada/invalid-config"
  static let invalidEvent = "colada/invalid-event"
  static let missingUser = "colada/missing-user"
  static let backendRejected = "colada/backend-rejected"
  static let deliveryFailed = "colada/delivery-failed"
  static let network = "colada/network"
  static let tokenExpired = "colada/token-expired"
  static let deviceIdentityUnavailable = "colada/device-identity-unavailable"
  static let trackingBlocked = "colada/tracking-blocked"
  static let unsupported = "colada/unsupported"
}

/// Builds the Pigeon error that carries a Colada code across to Dart.
///
/// `details` becomes the Dart `PlatformException.details` map that
/// `exception_mapper.dart` reads for structured fields such as `statusCode`
/// and `attempts`.
func coladaError(
  code: String,
  message: String,
  details: [String: Any]? = nil
) -> PigeonError {
  PigeonError(code: code, message: message, details: details)
}
