/// The Colada SDK facade.
library;

import 'attribution.dart';
import 'bridge.dart';
import 'config.dart';
import 'events.dart';
import 'exceptions.dart';
import 'logging.dart';

/// The Colada SDK. This is the only type you call.
///
/// ### Integration in three steps
///
/// **1. Initialize**, once, as early as possible:
///
/// ```dart
/// Future<void> main() async {
///   WidgetsFlutterBinding.ensureInitialized();
///   await Colada.initialize(
///     const ColadaConfig(
///       publicTenantKey: String.fromEnvironment('COLADA_TENANT_KEY'),
///     ),
///   );
///   runApp(const MyApp());
/// }
/// ```
///
/// Initialize before `runApp`, not from a widget. The SDK collects install
/// signals that are only available briefly after launch, and it cannot process
/// a deep link that arrives before it has started.
///
/// **2. Identify the user** after sign-up, after login, and on app start when
/// restoring a saved session:
///
/// ```dart
/// await Colada.setUser(user.id);
/// ```
///
/// **3. Track events** at the moments they happen. See [ColadaEvent].
///
/// Deep links need no step of their own: the plugin observes what the OS
/// delivers and reports it for you. See
/// [ColadaConfig.automaticDeepLinkForwarding].
///
/// ### What it guarantees
///
/// - **Never blocks.** Every method returns a `Future` that completes quickly;
///   network work happens in the background.
/// - **Only Colada types are thrown.** Every failure surfaces as a
///   [ColadaException], never a platform exception.
///
/// ### What differs by platform
///
/// The native Android and iOS SDKs are not perfectly parallel, and this package
/// does not pretend otherwise. Capabilities marked *Android only* or *iOS only*
/// in these docs behave differently on the other platform — see
/// `doc/PLATFORM_DIFFERENCES.md` for the complete list, and
/// [ColadaConfig.strictMode] for making those differences loud during
/// development.
abstract final class Colada {
  /// Starts the SDK. Call once, before `runApp`.
  ///
  /// Returns once the native SDK has started; attribution resolution and event
  /// delivery continue in the background. Calling this more than once is safe —
  /// later calls are ignored.
  ///
  /// Throws [ColadaInvalidConfigException] if [config] cannot be used. The
  /// check runs entirely in Dart, before anything reaches the native SDK, so an
  /// invalid key fails identically on both platforms.
  static Future<void> initialize(ColadaConfig config) async {
    config.validate();
    return ColadaBridge.instance.initialize(config);
  }

  /// Whether [initialize] has completed successfully.
  ///
  /// You should not normally need this — every method is safe to call
  /// regardless, and throws [ColadaNotInitializedException] if the SDK is not
  /// running. It exists for diagnostics.
  static Future<bool> get isInitialized =>
      ColadaBridge.instance.isInitialized();

  /// This device's stable Colada identifier, or `null` before [initialize].
  ///
  /// Survives app reinstall. Read-only by design: an app that can set this will
  /// eventually set it to something that is not unique per device, which
  /// silently corrupts attribution for every affected user. To carry over an
  /// identifier from a previous implementation, use
  /// [ColadaConfig.existingDeviceId].
  static Future<String?> get deviceId => ColadaBridge.instance.deviceId();

  /// Associates all subsequent events with a user.
  ///
  /// Call after sign-up, after login, **and** on app start when restoring a
  /// saved session. Identifying the user is not the same as a login *event*:
  /// restoring a session should call this and **not** fire [Login].
  ///
  /// [externalUserId] must be your own identifier for the user, and must be the
  /// same value your backend registers with Colada, or events will not link to
  /// their attribution.
  ///
  /// Throws [ColadaInvalidConfigException] if [externalUserId] is blank.
  static Future<void> setUser(String externalUserId) async {
    if (externalUserId.trim().isEmpty) {
      throw const ColadaInvalidConfigException(
        'externalUserId',
        'must not be blank.',
      );
    }
    return ColadaBridge.instance.setUser(externalUserId);
  }

  /// Clears the current user. Call on logout.
  ///
  /// Any events still queued for the outgoing user are sent before the identity
  /// is cleared, so one user's activity is never attributed to whoever logs in
  /// next. The device identifier is unchanged — it identifies the device, not
  /// the person.
  static Future<void> clearUser() => ColadaBridge.instance.clearUser();

  /// Reports a user-lifecycle event. See [ColadaEvent] for when to fire each.
  ///
  /// Throws [ColadaInvalidEventException] if the event is malformed — checked
  /// in Dart before anything crosses to the native SDK.
  ///
  /// ⚠️ **The returned `Future` means different things on each platform.** On
  /// Android it completes once the event is durably queued; delivery happens
  /// afterwards and survives a dropped connection, the app being killed, and a
  /// reboot. On iOS it completes once delivery has been *attempted*, and can
  /// throw [ColadaDeliveryFailedException] or
  /// [ColadaBackendRejectedException] — the event is still queued for retry in
  /// the first case. Do not gate your UI on this `Future` resolving.
  ///
  /// ⚠️ On iOS, tracking before [setUser] throws
  /// [ColadaMissingUserException]; on Android the event is held and released
  /// once a user is known. Call [setUser] first and the difference disappears.
  static Future<void> track(ColadaEvent event) async {
    event.validate();
    return ColadaBridge.instance.track(event.eventName, event.metadata);
  }

  /// Requests immediate delivery of any queued events.
  ///
  /// Rarely needed — events are delivered automatically, and the OS re-runs
  /// delivery when connectivity returns. Useful before a deliberate logout.
  ///
  /// It is a *request*, not a guarantee: an event whose backoff has not elapsed
  /// stays queued.
  static Future<void> flush() => ColadaBridge.instance.flush();

  /// The attribution resolved for this device, or `null` if it has not resolved
  /// yet.
  ///
  /// Prefer [attributionStream] — attribution usually resolves shortly *after*
  /// [initialize] returns, so reading this immediately afterwards will normally
  /// give you `null`.
  static Future<ColadaAttribution?> get attribution =>
      ColadaBridge.instance.currentAttribution();

  /// Attribution results, as they resolve.
  ///
  /// A broadcast stream that **replays the most recent result to a new
  /// listener**, so subscribing late cannot cause you to miss it. That matters
  /// more than it sounds: attribution typically resolves within a few hundred
  /// milliseconds of [initialize], often before your UI is ready to subscribe.
  /// Without the replay, deferred deep links would work on a slow network and
  /// mysteriously fail on a fast one.
  ///
  /// ```dart
  /// Colada.attributionStream.listen((result) {
  ///   if (result.matched) log('campaign: ${result.utmCampaign}');
  /// });
  /// ```
  static Stream<ColadaAttribution> get attributionStream =>
      ColadaBridge.instance.attributionStream;

  /// Returns the pending deferred deep link, or `null` if there is none.
  ///
  /// **Consumes it:** the second call returns `null`. That is deliberate — a
  /// returning user should not be teleported to a campaign landing page on
  /// every launch.
  ///
  /// Call once, after the user reaches a point where navigation makes sense —
  /// typically after your splash screen hands off, or after sign-up. Check
  /// [ColadaDeferredDeepLink.hasDestination] before navigating.
  static Future<ColadaDeferredDeepLink?> consumeDeferredDeepLink() =>
      ColadaBridge.instance.consumeDeferredDeepLink();

  /// Reports a deep link so its attribution parameters can be captured.
  ///
  /// **You normally do not call this.** The plugin forwards incoming links for
  /// you; see [ColadaConfig.automaticDeepLinkForwarding]. Call it only if you
  /// set that to `false`, or for a link that reaches your app by some route the
  /// OS does not deliver as a URL.
  ///
  /// Safe to call with any link, including one that carries no attribution
  /// parameters — those are ignored. The same link reported twice is counted
  /// once.
  static Future<void> handleDeepLink(Uri uri) =>
      ColadaBridge.instance.handleDeepLink(uri);

  /// Diagnostic log records from the SDK.
  ///
  /// A broadcast stream. Useful for piping SDK diagnostics into your own crash
  /// reporter, and for seeing why attribution behaved the way it did. Set
  /// [ColadaConfig.debug] for verbose records.
  ///
  /// ⚠️ Coverage differs by platform — see [ColadaLogRecord].
  static Stream<ColadaLogRecord> get logs => ColadaBridge.instance.logs;
}
