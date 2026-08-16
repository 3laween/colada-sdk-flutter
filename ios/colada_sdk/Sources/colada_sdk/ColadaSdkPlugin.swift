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
///  - **10** identity and events: `setUser` / `clearUser` / `track` / `flush`,
///    including the translation onto the native SDK's fixed event vocabulary
///    and fixed metadata shape.
///  - **11** attribution: the resolved-attribution stream, `currentAttribution`
///    and `consumeDeferredDeepLink`, flattened into the shape Android reports.
///  - **12** automatic deep-link forwarding: cold start, custom schemes and
///    Universal Links, plus the pre-initialize buffer.
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

  /// Set when Dart subscribes to the attribution stream.
  fileprivate var attributionEventSink: PigeonEventSink<NativeAttribution>?

  /// Consumes the native `observeAttribution()` stream while Dart is
  /// subscribed. Cancelled on unsubscribe and on engine detach — the stream
  /// never finishes on its own, so a task left running would outlive the engine
  /// it was feeding.
  private var attributionTask: Task<Void, Never>?

  private lazy var attributionStreamHandler = BridgeAttributionStreamHandler(plugin: self)

  /// Links the OS delivered before initialize. Replayed once the SDK is up.
  private var pendingLinks: [URL] = []

  private static let maxPendingLinks = 5

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
    AttributionResolvedStreamHandler.register(
      with: registrar.messenger(),
      streamHandler: instance.attributionStreamHandler
    )
    // Retained so the instance outlives `register`.
    registrar.publish(instance)
    // Subscribes the plugin to the app delegate's URL callbacks. Without this
    // the three methods below are simply never called, and nothing about the
    // build would tell you so — the integrator would just never be attributed.
    registrar.addApplicationDelegate(instance)
  }

  public func detachFromEngine(for registrar: FlutterPluginRegistrar) {
    ColadaHostApiSetup.setUp(binaryMessenger: registrar.messenger(), api: nil)
    stopObservingAttribution()
    logEventSink = nil
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
          // Phase 12: replay links the OS delivered before the SDK was up.
          self.drainPendingLinks()
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

  // MARK: - ColadaHostApi: identity and events (Phase 10)

  func setUser(externalUserId: String, completion: @escaping (Result<Void, Error>) -> Void) {
    Task {
      await ColadaSDK.shared.setExternalUserId(externalUserId)
      self.onMain { completion(.success(())) }
    }
  }

  func clearUser(completion: @escaping (Result<Void, Error>) -> Void) {
    Task {
      // The native SDK models "no user" as a nil external id. Note the
      // divergence this leaves: Android flushes the outgoing user's queued
      // events before clearing, iOS does not.
      await ColadaSDK.shared.setExternalUserId(nil)
      self.onMain { completion(.success(())) }
    }
  }

  func track(
    eventName: String,
    metadata: [String: Any?],
    completion: @escaping (Result<Void, Error>) -> Void
  ) {
    // 1. Name to enum. The native vocabulary is fixed at nine cases, and its raw
    //    values are the same wire strings Dart sends, so an unrecognised name is
    //    exactly a Dart `RawEvent` — which this platform cannot express. Never
    //    drop it silently: an event the app believes it sent and the backend
    //    never sees is the worst possible failure here.
    guard let name = AttributionEventName(rawValue: eventName) else {
      completion(
        .failure(
          unsupported(
            feature: "custom event names",
            message:
              "The native iOS SDK accepts only its nine fixed event names, so '\(eventName)' "
              + "cannot be sent. Use one of the typed ColadaEvent subclasses instead.")))
      return
    }

    // 2. Metadata to the native SDK's fixed shape. Anything it has no field for
    //    cannot be transmitted by this binary at all, so report what was lost
    //    rather than letting the app believe it arrived.
    let userInfo = Self.userInfo(from: metadata)
    let sendAsRegistration = name == .completeRegistration && userInfo != nil
    let transmittable =
      sendAsRegistration ? Self.registrationKeys : Self.metadataKeys
    let dropped = metadata.keys.filter { !transmittable.contains($0) }.sorted()

    if !dropped.isEmpty,
      let error = reportUnsupported(
        feature: "custom event metadata",
        detail:
          "The native iOS SDK transmits only \(transmittable.sorted().joined(separator: ", ")) "
          + "on \(eventName). Dropped: \(dropped.joined(separator: ", ")). The event itself "
          + "was still sent.")
    {
      completion(.failure(error))
      return
    }

    Task {
      do {
        if sendAsRegistration {
          // 3. Registration routing. reportRegistration is the only call that
          //    can carry user data, and the only way name/email/phoneNumber
          //    leave the device.
          _ = try await ColadaSDK.shared.reportRegistration(userInfo: userInfo)
        } else {
          _ = try await ColadaSDK.shared.reportEvent(
            name, metadata: Self.eventMetadata(from: metadata))
        }
        self.onMain { completion(.success(())) }
      } catch {
        // Includes .missingExternalUserId — tracking before setUser is a
        // hard failure on iOS where Android holds the event. Mapped to
        // ColadaMissingUserException so the app can tell the two apart.
        self.onMain { completion(.failure(self.mapNativeError(error))) }
      }
    }
  }

  func flush(completion: @escaping (Result<Void, Error>) -> Void) {
    Task {
      await ColadaSDK.shared.flush()
      self.onMain { completion(.success(())) }
    }
  }

  // MARK: - ColadaHostApi: attribution (Phase 11)

  func currentAttribution(completion: @escaping (Result<NativeAttribution?, Error>) -> Void) {
    // Like deviceId, this suspends behind an unfinished configure(); answering
    // Dart's documented "null until it resolves" is better than hanging.
    guard initialized else {
      completion(.success(nil))
      return
    }
    Task {
      let result = await ColadaSDK.shared.lastAttribution
      let native = result.map(Self.attribution(from:))
      self.onMain { completion(.success(native)) }
    }
  }

  func consumeDeferredDeepLink(
    completion: @escaping (Result<NativeDeferredDeepLink?, Error>) -> Void
  ) {
    guard initialized else {
      completion(.success(nil))
      return
    }
    Task {
      // One-shot, and re-armed by the next successful handshake — where Android
      // re-arms only when the app asks it to. Documented, not papered over.
      let link = await ColadaSDK.shared.consumeDeferredDeepLink()
      let native = link.map(Self.deferredDeepLink(from:))
      self.onMain { completion(.success(native)) }
    }
  }

  // MARK: - ColadaHostApi: deep links (Phase 12)

  func handleDeepLink(url: String, completion: @escaping (Result<Void, Error>) -> Void) {
    // The manual escape hatch, reached only when the host opted out of
    // automatic forwarding. Forwarded unconditionally: the host asked for this
    // one explicitly, and the native SDK de-duplicates a link it has already
    // seen, so an overlap with the automatic path is harmless.
    if let parsed = URL(string: url) {
      report(parsed)
    } else {
      emitLog(ColadaLogLevel.warn, "Ignored a deep link that is not a valid URL: \(url)")
    }
    // Fire-and-forget, matching Android and the Dart API's own contract: the
    // handshake result is already broadcast on the attribution stream, so
    // waiting for it here would only delay the caller.
    completion(.success(()))
  }

  // MARK: - Automatic deep-link forwarding (Phase 12)
  //
  // The integrator writes no platform code: the plugin observes what the OS
  // delivers and reports it. Every handler below returns false — this plugin is
  // an observer of the link, never its owner, so app_links and friends still
  // see it.

  public func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any] = [:]
  ) -> Bool {
    // Cold start. The URL is delivered here before the Flutter engine — and so
    // before Dart can have called initialize — which is the whole reason the
    // buffer below exists.
    if let url = launchOptions[.url] as? URL {
      forward(url)
    }
    // Cold start via a Universal Link arrives as an activity dictionary instead.
    if let activities = launchOptions[.userActivityDictionary] as? [AnyHashable: Any] {
      for case let activity as NSUserActivity in activities.values {
        forward(universalLink: activity)
      }
    }
    // Never false: this is the launch path, and a plugin has no business
    // reporting that the app failed to launch.
    return true
  }

  public func application(
    _ application: UIApplication,
    open url: URL,
    options: [UIApplication.OpenURLOptionsKey: Any] = [:]
  ) -> Bool {
    forward(url)
    return false
  }

  public func application(
    _ application: UIApplication,
    continue userActivity: NSUserActivity,
    restorationHandler: @escaping ([UIUserActivityRestoring]) -> Void
  ) -> Bool {
    // Universal Links, which is how most real campaign links arrive.
    forward(universalLink: userActivity)
    return false
  }

  private func forward(universalLink activity: NSUserActivity) {
    guard activity.activityType == NSUserActivityTypeBrowsingWeb,
      let url = activity.webpageURL
    else {
      return
    }
    forward(url)
  }

  /// Reports a link, or buffers it until the SDK is configured.
  ///
  /// The buffer is not there to cover the configure race — the native SDK waits
  /// for an unfinished `configure()` by itself. It is there because
  /// `automaticDeepLinkForwarding` is not *known* until initialize crosses from
  /// Dart, and forwarding a link the host meant to own itself cannot be undone.
  /// Bounded, so a pathological sender cannot grow it without limit.
  private func forward(_ url: URL) {
    guard initialized else {
      if pendingLinks.count >= Self.maxPendingLinks {
        pendingLinks.removeFirst()
      }
      pendingLinks.append(url)
      emitLog(ColadaLogLevel.debug, "Buffered a deep link until initialize: \(url)")
      return
    }
    guard autoForward else {
      emitLog(
        ColadaLogLevel.debug,
        "Ignored a deep link because automaticDeepLinkForwarding is off: \(url)")
      return
    }
    report(url)
  }

  /// Replays links buffered before initialize. Called once initialize succeeds.
  private func drainPendingLinks() {
    let links = pendingLinks
    pendingLinks.removeAll()
    if links.isEmpty { return }
    // In manual mode those links belong to the host, so drop them rather than
    // reporting links it never asked us to report.
    guard autoForward else {
      emitLog(
        ColadaLogLevel.debug,
        "Dropped \(links.count) buffered deep link(s): automaticDeepLinkForwarding is off.")
      return
    }
    emitLog(
      ColadaLogLevel.debug,
      "Replaying \(links.count) deep link(s) buffered before initialize.")
    for url in links { report(url) }
  }

  /// Hands a link to the native SDK. The result is discarded on purpose: it is
  /// already broadcast on the attribution stream, and the Dart API is
  /// fire-and-forget on both platforms.
  private func report(_ url: URL) {
    // The only diagnostic there is on this platform: the native iOS SDK has no
    // log sink, so without this an integrator debugging attribution cannot tell
    // "the link never reached the SDK" from "the SDK saw it and dropped it".
    emitLog(ColadaLogLevel.debug, "Reported a deep link: \(url)")
    Task { _ = await ColadaSDK.shared.handleDeepLink(url) }
  }

  // MARK: - Attribution observation (Phase 11)

  /// Starts feeding the attribution event channel.
  ///
  /// Deliberately started when Dart subscribes rather than at `initialize`:
  /// `observeAttribution()` replays the current `lastAttribution` to each new
  /// consumer, so opening the stream here is what makes a late subscriber still
  /// receive a result that resolved seconds earlier. Attribution usually
  /// resolves before any UI is ready to listen, so this is the normal case, not
  /// the edge case. The Android bridge attaches its native listener at the same
  /// moment, for the same reason.
  fileprivate func startObservingAttribution(sink: PigeonEventSink<NativeAttribution>) {
    attributionEventSink = sink
    attributionTask?.cancel()
    attributionTask = Task { [weak self] in
      let stream = await ColadaSDK.shared.observeAttribution()
      for await result in stream {
        guard let self, !Task.isCancelled else { return }
        let native = Self.attribution(from: result)
        // Values arrive on the SDK's own executor; Flutter requires event-sink
        // writes to come from the platform thread.
        self.onMain { self.attributionEventSink?.success(native) }
      }
    }
  }

  fileprivate func stopObservingAttribution() {
    attributionTask?.cancel()
    attributionTask = nil
    attributionEventSink = nil
  }

  // MARK: - Attribution mapping (Phase 11)

  /// Flattens the native handshake result into the shape Dart sees on both
  /// platforms.
  ///
  /// Two deliberate differences from a straight field copy:
  ///
  /// - The native result is flat, with the deferred-deep-link fields sitting
  ///   alongside the campaign ones. Android nests them, so they are nested here
  ///   too and the Dart model has one shape everywhere.
  /// - `asn`, `osVersion`, `screenResolution` and `rawLink` have no Android
  ///   counterpart, so rather than dropping them they are folded into `extras`,
  ///   where the Dart model already carries anything neither SDK models.
  private static func attribution(from result: AttributionHandshakeResult) -> NativeAttribution {
    var extras: [String: Any?] = [:]
    if let asn = result.asn { extras["asn"] = asn }
    if let osVersion = result.osVersion { extras["osVersion"] = osVersion }
    if let screenResolution = result.screenResolution {
      extras["screenResolution"] = screenResolution
    }
    if let rawLink = result.rawLink { extras["rawLink"] = rawLink }

    return NativeAttribution(
      matched: result.matched,
      // The backend's own wire string, parsed in Dart with an `unknown`
      // fallback so a strategy added later never breaks a plugin in the field.
      matchMethod: result.matchMethod,
      utmSource: result.utmSource,
      utmCampaign: result.utmCampaign,
      utmMedium: result.utmMedium,
      utmContent: result.utmContent,
      utmTerm: result.utmTerm,
      clickId: result.clickId,
      attributionId: result.attributionId,
      tenantKey: result.tenantKey,
      deferredDeepLink: deferredDeepLink(from: result),
      extras: extras
    )
  }

  /// Synthesises the nested deferred deep link, or nil when the handshake
  /// carried no destination — matching Android, which reports nil rather than
  /// an empty target.
  private static func deferredDeepLink(from result: AttributionHandshakeResult)
    -> NativeDeferredDeepLink?
  {
    let isSubscription = result.isCoffeeSubscription ?? false
    guard result.attributionStoreId != nil || result.attributionMenuItemId != nil
      || isSubscription
    else {
      return nil
    }
    return NativeDeferredDeepLink(
      storeId: result.attributionStoreId,
      menuItemId: result.attributionMenuItemId,
      isCoffeeSubscription: isSubscription,
      // Always empty on iOS: the native SDK surfaces no additional parameters
      // for a deferred deep link, where Android carries the handshake's extras.
      extras: [:]
    )
  }

  private static func deferredDeepLink(from link: DeferredDeepLink) -> NativeDeferredDeepLink {
    NativeDeferredDeepLink(
      storeId: link.storeId,
      menuItemId: link.menuItemId,
      isCoffeeSubscription: link.isCoffeeSubscription ?? false,
      extras: [:]
    )
  }

  // MARK: - Event metadata (Phase 10)

  /// Metadata keys the native `AttributionEventMetadata` can carry.
  ///
  /// Deliberately not `phoneNumber`: the backend accepts it there, but the
  /// native SDK dropped it from this struct on privacy grounds and its privacy
  /// manifest no longer declares it. On a registration it still travels, via
  /// `ColadaUserInfo`.
  private static let metadataKeys: Set<String> = ["amount", "currency", "orderId"]

  /// Metadata keys `reportRegistration` can carry, via `ColadaUserInfo`.
  private static let registrationKeys: Set<String> = ["name", "email", "phoneNumber"]

  /// Builds the user data for a registration, or nil when the event carries
  /// none — in which case it is reported as an ordinary event instead.
  private static func userInfo(from metadata: [String: Any?]) -> ColadaUserInfo? {
    let name = string(metadata, "name")
    let email = string(metadata, "email")
    let phoneNumber = string(metadata, "phoneNumber")
    if name == nil, email == nil, phoneNumber == nil { return nil }
    return ColadaUserInfo(name: name, email: email, phoneNumber: phoneNumber)
  }

  /// Builds the native metadata struct, or nil when nothing maps onto it.
  ///
  /// Every field is passed explicitly, including the nil ones: the native
  /// initialiser defaults `currency` to "SAR", and letting that default apply
  /// would attach a currency the app never sent.
  private static func eventMetadata(from metadata: [String: Any?]) -> AttributionEventMetadata? {
    let amount = double(metadata, "amount")
    let currency = string(metadata, "currency")
    let orderId = string(metadata, "orderId")
    if amount == nil, currency == nil, orderId == nil { return nil }
    return AttributionEventMetadata(amount: amount, currency: currency, orderId: orderId)
  }

  /// Reads a String, or nil if absent, null, or another type.
  private static func string(_ metadata: [String: Any?], _ key: String) -> String? {
    guard let wrapped = metadata[key] else { return nil }
    return wrapped as? String
  }

  /// Reads a number as a Double.
  ///
  /// Dart sends `double`, but a whole number can arrive as an Int through the
  /// channel codec, so accept any NSNumber rather than only Double.
  private static func double(_ metadata: [String: Any?], _ key: String) -> Double? {
    guard let wrapped = metadata[key] else { return nil }
    if let value = wrapped as? Double { return value }
    if let value = wrapped as? NSNumber { return value.doubleValue }
    return nil
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
/// Starts and stops the native attribution observation with Dart's
/// subscription.
///
/// Weak for the same reason as the log handler: the event channel outlives a
/// detached plugin, and a strong reference here would keep it alive with it.
private final class BridgeAttributionStreamHandler: AttributionResolvedStreamHandler {
  private weak var plugin: ColadaSdkPlugin?

  init(plugin: ColadaSdkPlugin) {
    self.plugin = plugin
  }

  override func onListen(withArguments arguments: Any?, sink: PigeonEventSink<NativeAttribution>) {
    plugin?.startObservingAttribution(sink: sink)
  }

  override func onCancel(withArguments arguments: Any?) {
    plugin?.stopObservingAttribution()
  }
}

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
