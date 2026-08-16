import Colada
import Flutter
import UIKit

/// Colada Flutter plugin — iOS entry point.
///
/// Bridges the Pigeon-generated `ColadaHostApi` and the event channels onto the
/// published native Colada iOS SDK (CocoaPods `Colada` 0.1.1 / Swift package
/// `colada-sdk-ios` v0.1.1), with no changes to that SDK.
///
/// Built across Phases 9 to 12:
///  - **9** lifecycle: ``initialize(config:completion:)`` /
///    ``isInitialized(completion:)`` / ``deviceId(completion:)``, the native
///    error mapper, and the log event channel the later phases report through.
///  - **10** identity and events, **11** attribution, **12** deep links.
///
/// ### Threading
///
/// Pigeon invokes every method on the platform (main) thread. The native SDK is
/// actor-isolated and every call into it is `async`, so each one runs in a
/// `Task` and hops its Pigeon callback back to the main thread: Flutter requires
/// channel replies and event-sink writes to originate there.
///
/// ### What the bridge owns on iOS
///
/// `isInitialized`, `debug`, `strictMode` and `existingDeviceId` have no native
/// equivalent — the Android SDK has all four, the iOS SDK none. The bridge
/// therefore tracks them itself: its own initialized flag, its own verbose
/// logging, and the warn-versus-throw tiers for capabilities iOS cannot offer.
public class ColadaSdkPlugin: NSObject, FlutterPlugin, ColadaHostApi {

  /// The bridge's own flag: true once `configure()` has returned without
  /// throwing. The native SDK exposes nothing equivalent.
  private var initialized = false

  /// Bridge-held configuration — none of these reach the native SDK.
  private var debug = false
  private var strictMode = false
  private var autoForward = true

  /// Set when Dart subscribes to the log stream, cleared when it cancels.
  /// Records emitted while it is nil are dropped, exactly as they are on
  /// Android when nothing is listening.
  fileprivate var logEventSink: PigeonEventSink<NativeLogRecord>?

  private lazy var logStreamHandler = BridgeLogStreamHandler(plugin: self)

  public static func register(with registrar: FlutterPluginRegistrar) {
    let instance = ColadaSdkPlugin()
    // ColadaHostApiSetup, not ColadaHostApi: in Swift, Pigeon generates the API
    // as a protocol and puts setUp on a separate generated class. (Kotlin
    // differs — there setUp lives in the interface's companion object.)
    ColadaHostApiSetup.setUp(binaryMessenger: registrar.messenger(), api: instance)
    // The log channel is registered here, not in Phase 11 with the attribution
    // channel, because it is the only route a bridge-level warning has to reach
    // the app and Phase 9 already emits one (existingDeviceId, below).
    LogEmittedStreamHandler.register(
      with: registrar.messenger(),
      streamHandler: instance.logStreamHandler
    )
    // Retained so the instance outlives `register`; also the hook the deep-link
    // callbacks in Phase 12 need.
    registrar.publish(instance)
    // The attribution event channel is registered in Phase 11, together with
    // the native observation task that feeds it.
  }

  // MARK: - ColadaHostApi: lifecycle (Phase 9)

  func initialize(config: NativeConfig, completion: @escaping (Result<Void, Error>) -> Void) {
    debug = config.debug
    strictMode = config.strictMode
    autoForward = config.automaticDeepLinkForwarding

    // R1 — the native iOS SDK has no way to adopt an identifier minted by a
    // previous implementation, so an app migrating from one gets a fresh
    // identity here, detached from its attribution history on Android. Nothing
    // the bridge can do about it under the native-freeze decision; what it can
    // do is refuse to be quiet about it.
    if config.existingDeviceId != nil,
      let error = reportUnsupported(
        feature: "existingDeviceId",
        detail:
          "The native iOS SDK cannot adopt an existing device identifier, so this device "
          + "will be given a new one. Attribution history recorded against the old "
          + "identifier will not follow it.")
    {
      completion(.failure(error))
      return
    }

    Task {
      do {
        // publicTenantKey doubles as the API key on every backend call. The
        // backend host is not configurable: a public package must not let
        // anyone point the SDK at an arbitrary host, and on iOS it is a
        // compile-time constant in the native binary regardless.
        try await ColadaSDK.shared.configure(apiKey: config.publicTenantKey)
        self.onMain {
          self.initialized = true
          self.emitLog(ColadaLogLevel.debug, "Native Colada iOS SDK configured.")
          completion(.success(()))
        }
      } catch {
        self.onMain { completion(.failure(self.mapNativeError(error))) }
      }
    }
  }

  func isInitialized(completion: @escaping (Result<Bool, Error>) -> Void) {
    completion(.success(initialized))
  }

  func deviceId(completion: @escaping (Result<String?, Error>) -> Void) {
    // `deviceIdentity` suspends until an unfinished `configure()` completes, so
    // reading it before initialize would leave the Dart Future hanging forever
    // rather than answering it. Dart's documented contract is null before
    // initialize; answer that here instead of asking.
    guard initialized else {
      completion(.success(nil))
      return
    }
    Task {
      let identity = await ColadaSDK.shared.deviceIdentity
      self.onMain { completion(.success(identity)) }
    }
  }

  // MARK: - ColadaHostApi
  //
  // Phase 10 replaces the identity and event calls, Phase 11 attribution,
  // Phase 12 deep links.

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

  // MARK: - Unsupported capabilities (plan section 3e)

  /// Handles a capability iOS does not have and that is harmless to skip
  /// (tier 2): normally a warning on the log stream, but a thrown
  /// `ColadaUnsupportedException` under `strictMode`, which is what strictMode
  /// is for. Returns the error to fail with, or nil to carry on.
  private func reportUnsupported(feature: String, detail: String) -> PigeonError? {
    if strictMode {
      return unsupported(feature: feature, message: detail)
    }
    emitLog(ColadaLogLevel.warn, "\(feature) is not supported on iOS. \(detail)")
    return nil
  }

  /// Tier 3 — a capability whose absence cannot be papered over silently.
  private func unsupported(feature: String, message: String) -> PigeonError {
    coladaError(
      code: ColadaErrorCode.unsupported,
      message: message,
      details: ["feature": feature, "platform": "iOS"]
    )
  }

  // MARK: - Logging

  /// Emits a bridge-level log record. Dropped when nothing is listening.
  ///
  /// `debug` records are emitted only when the integrator asked for them; the
  /// native iOS SDK has no log sink of its own, so every record on this stream
  /// comes from here.
  fileprivate func emitLog(_ level: String, _ message: String, error: String? = nil) {
    if level == ColadaLogLevel.debug && !debug { return }
    let record = NativeLogRecord(level: level, message: message, error: error)
    onMain { self.logEventSink?.success(record) }
  }

  // MARK: - Error mapping

  /// Maps a native `ColadaError` onto the shared error-code vocabulary.
  ///
  /// Every case has a home: an unmapped native error would reach Dart with the
  /// Swift type's description as its code, which matches no typed exception at
  /// all and degrades to a misleading network failure.
  private func mapNativeError(_ error: Error) -> PigeonError {
    guard let error = error as? ColadaError else {
      // Not a Colada error at all — a cancelled Task, say. Report it rather
      // than swallowing it; Dart degrades an unrecognised code to
      // ColadaNetworkException carrying this message.
      return coladaError(
        code: ColadaErrorCode.network,
        message: "The native Colada SDK failed: \(error)"
      )
    }

    switch error {
    case .deliveryFailed(let attempts):
      return coladaError(
        code: ColadaErrorCode.deliveryFailed,
        message: "Delivery failed after \(attempts) attempts. The event is still queued.",
        details: ["attempts": attempts]
      )

    case .encodingFailed:
      return coladaError(
        code: ColadaErrorCode.invalidEvent,
        message: "The request body could not be encoded."
      )

    case .networkError:
      return coladaError(
        code: ColadaErrorCode.network,
        message: "The request could not reach the Colada backend."
      )

    case .missingExternalUserId:
      return coladaError(
        code: ColadaErrorCode.missingUser,
        message: "Call Colada.setUser before tracking an event on iOS."
      )

    case .backendRejected(let statusCode, let message):
      var details: [String: Any] = ["statusCode": statusCode]
      if let message { details["serverMessage"] = message }
      return coladaError(
        code: ColadaErrorCode.backendRejected,
        message: message ?? "The Colada backend rejected the request.",
        details: details
      )

    case .invalidConversionValue:
      // Unreachable from this bridge: SKAdNetwork is iOS-only and deliberately
      // not exposed in the Dart API. Mapped anyway so the switch stays
      // exhaustive and a future exposure cannot land an untyped error.
      return coladaError(
        code: ColadaErrorCode.invalidEvent,
        message: "The SKAdNetwork conversion value was outside the valid range."
      )

    case .blockedByTrackingPrevention:
      return coladaError(
        code: ColadaErrorCode.trackingBlocked,
        message: "iOS blocked the request because App Tracking Transparency was not granted."
      )

    case .tokenExpired:
      return coladaError(
        code: ColadaErrorCode.tokenExpired,
        message: "The Colada session token expired and could not be renewed."
      )

    case .deviceIdentityUnavailable:
      return coladaError(
        code: ColadaErrorCode.deviceIdentityUnavailable,
        message: "The device identity could not be read from the Keychain. Try again later."
      )
    }
  }

  // MARK: - Helpers

  /// Runs `block` on the main thread, immediately if already there.
  ///
  /// Pigeon replies and event-sink writes must come from the platform thread,
  /// and every native call returns on the SDK's own executor instead.
  fileprivate func onMain(_ block: @escaping () -> Void) {
    if Thread.isMainThread {
      block()
    } else {
      DispatchQueue.main.async(execute: block)
    }
  }

  // Must be a Pigeon `PigeonError`, not a custom Error type: the generated
  // `wrapError` only forwards code/message/details for PigeonError, and falls
  // back to the type's description for anything else. A custom error here would
  // reach Dart with a code that maps to no typed exception at all.
  private static func notImplemented(_ method: String) -> PigeonError {
    coladaError(
      code: ColadaErrorCode.notInitialized,
      message: "Colada.\(method) is not wired on iOS yet (arrives in Phases 10-12)."
    )
  }
}

/// Holds the log stream's sink for the plugin.
///
/// Weak, because the event channel retains this handler for the life of the
/// engine while the plugin is retained by the registrar; a strong reference
/// here would keep the plugin alive after a detached engine should have
/// released it.
private final class BridgeLogStreamHandler: LogEmittedStreamHandler {
  private weak var plugin: ColadaSdkPlugin?

  init(plugin: ColadaSdkPlugin) {
    self.plugin = plugin
  }

  override func onListen(withArguments arguments: Any?, sink: PigeonEventSink<NativeLogRecord>) {
    plugin?.logEventSink = sink
  }

  override func onCancel(withArguments arguments: Any?) {
    plugin?.logEventSink = nil
  }
}

/// Log levels reported to Dart.
///
/// Wire strings, matching `ColadaLogLevel.wireValue` in `lib/src/logging.dart`.
/// An unrecognised value degrades to `info` there rather than throwing — a log
/// record is diagnostic output and must never be the thing that fails.
enum ColadaLogLevel {
  static let debug = "debug"
  static let info = "info"
  static let warn = "warn"
  static let error = "error"
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
