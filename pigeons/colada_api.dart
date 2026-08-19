// Pigeon schema — the Dart <-> native contract for the Colada plugin.
//
// This file is NOT shipped to consumers and is not part of the public API. It
// is the input to code generation; run:
//
//   dart run pigeon --input pigeons/colada_api.dart \
//     && dart format lib/src/messages.g.dart
//
// and commit the three generated files. The format step is not optional: pigeon
// does not emit dart-format-clean Dart, so without it the repo's format gate
// and its regeneration gate contradict each other — one fails whichever way you
// commit. CI runs the same two commands and diffs the result, so a stale
// generated file cannot merge.
//
// ## Why these types are not the public models
//
// The types below are deliberately flat, primitive and boring. The public
// models in lib/src/ (ColadaConfig, ColadaEvent, ColadaAttribution, ...) are
// hand-written, documented and stable — integrators live with them forever.
// These are an implementation detail that may churn freely. Mapping between the
// two happens in lib/src/, in one place.
//
// ## Why enums cross as Strings
//
// `matchMethod` and log `level` are Strings here, not Pigeon enums. A Pigeon
// enum fails on a value it does not recognise, which would mean an older
// plugin in the field breaking the moment the backend adds a new match
// strategy. Crossing as a String lets ColadaMatchMethod.fromWire degrade to
// `unknown` instead — the same graceful-degradation contract both native SDKs
// already implement.

import 'package:pigeon/pigeon.dart';

@ConfigurePigeon(
  PigeonOptions(
    dartOut: 'lib/src/messages.g.dart',
    kotlinOut: 'android/src/main/kotlin/io/coladaapp/sdk/flutter/Messages.g.kt',
    kotlinOptions: KotlinOptions(package: 'io.coladaapp.sdk.flutter'),
    swiftOut: 'ios/colada_sdk/Sources/colada_sdk/Messages.g.swift',
    // Set once, at the top level. Passing copyrightHeader inside
    // SwiftOptions/KotlinOptions instead crashes pigeon 27.3.0 with a
    // List<dynamic> cast error in SwiftOptions.fromList.
    copyrightHeader: 'pigeons/copyright_header.txt',
  ),
)

/// Configuration handed to the native SDK at startup.
///
/// `debug`, `strictMode` and `existingDeviceId` have no native equivalent on
/// iOS. They still cross, because the iOS bridge holds them itself: they decide
/// whether an unsupported capability warns or throws, and whether the bridge
/// emits verbose log records.
class NativeConfig {
  NativeConfig({
    required this.publicTenantKey,
    required this.debug,
    required this.strictMode,
    required this.automaticDeepLinkForwarding,
    this.existingDeviceId,
  });

  String publicTenantKey;
  bool debug;
  bool strictMode;
  bool automaticDeepLinkForwarding;
  String? existingDeviceId;
}

/// Deferred deep-link target.
///
/// The destination is carried entirely in [extras]. Both native SDKs now expose
/// the deferred deep link as a single `Map<String, String>`: `storeId`,
/// `menuItemId` and `isCoffeeSubscription` appear there under those exact keys
/// when present, alongside any tenant-specific destination fields. There are no
/// typed destination properties anymore, so the Dart layer sees one shape on
/// both platforms.
class NativeDeferredDeepLink {
  NativeDeferredDeepLink({
    required this.extras,
  });

  Map<String, String> extras;
}

/// A resolved attribution.
///
/// `matchMethod` is the raw backend string — see the note at the top of this
/// file. `extras` carries the campaign destination and any tenant params as a
/// string map — the same map [deferredDeepLink] exposes — so a backend field
/// neither SDK models is still readable. (It is typed `Object?` here only to
/// keep the public Dart model's `extras` type stable; both SDKs send strings.)
class NativeAttribution {
  NativeAttribution({
    required this.matched,
    required this.extras,
    this.matchMethod,
    this.utmSource,
    this.utmCampaign,
    this.utmMedium,
    this.utmContent,
    this.utmTerm,
    this.clickId,
    this.attributionId,
    this.tenantKey,
    this.deferredDeepLink,
  });

  bool matched;
  String? matchMethod;
  String? utmSource;
  String? utmCampaign;
  String? utmMedium;
  String? utmContent;
  String? utmTerm;
  String? clickId;
  String? attributionId;
  String? tenantKey;
  NativeDeferredDeepLink? deferredDeepLink;
  Map<String, Object?> extras;
}

/// One diagnostic log record.
///
/// `level` is a String for the same reason `matchMethod` is — an unrecognised
/// level must degrade, never throw, because this is the channel that reports
/// problems and it cannot be the thing that fails.
class NativeLogRecord {
  NativeLogRecord({
    required this.level,
    required this.message,
    this.error,
  });

  String level;
  String message;
  String? error;
}

/// Calls from Dart into the native SDK.
///
/// Every method is `@async`: the iOS SDK is actor-isolated and genuinely
/// asynchronous, and Android must not block the platform thread. Errors are
/// raised natively with a Colada error code, which the Dart layer maps back to
/// the typed exceptions in `lib/src/exceptions.dart`.
@HostApi()
abstract class ColadaHostApi {
  /// Starts the native SDK. Argument validation has already happened in Dart.
  @async
  void initialize(NativeConfig config);

  /// Whether the native SDK is running.
  ///
  /// On iOS there is no native equivalent, so the bridge reports its own flag,
  /// set once `configure()` returns without throwing.
  @async
  bool isInitialized();

  /// This device's stable Colada identifier, or null before initialize.
  @async
  String? deviceId();

  /// Associates subsequent events with a user.
  @async
  void setUser(String externalUserId);

  /// Clears the current user.
  ///
  /// Maps to `clearUser()` on Android and `setExternalUserId(nil)` on iOS.
  @async
  void clearUser();

  /// Reports an event by wire name plus a flat metadata map.
  ///
  /// This shape is deliberate: the native Android SDK already exposes
  /// `track(eventName, metadata)` and `ColadaEvent.of(name, map)` built for
  /// exactly this, so the bridge reuses its validation rather than duplicating
  /// it. The iOS bridge does more work here — it maps the name onto the fixed
  /// `AttributionEventName` enum, splits the metadata into the native SDK's
  /// fixed struct, routes a registration carrying user data to
  /// `reportRegistration`, and reports any key it could not transmit.
  @async
  void track(String eventName, Map<String, Object?> metadata);

  /// Requests immediate delivery of queued events.
  @async
  void flush();

  /// The attribution resolved so far, or null.
  @async
  NativeAttribution? currentAttribution();

  /// Consumes the pending deferred deep link. Returns null on a second call.
  @async
  NativeDeferredDeepLink? consumeDeferredDeepLink();

  /// Reports a deep link.
  ///
  /// Normally called by the plugin itself; only reaches here from Dart when the
  /// host opted out of automatic forwarding.
  @async
  void handleDeepLink(String url);
}

/// Streams from native into Dart.
///
/// Both replay their most recent value to a new listener, because both native
/// SDKs do: attribution typically resolves before any UI is ready to subscribe,
/// and without the replay a deferred deep link would work on a slow network and
/// fail on a fast one.
@EventChannelApi()
abstract class ColadaEventChannels {
  /// Attribution results, as they resolve.
  NativeAttribution attributionResolved();

  /// Diagnostic log records.
  ///
  /// Both native SDKs now expose a log sink the bridge registers at
  /// `configure`, so records come from the native SDK on Android and iOS alike,
  /// plus the bridge's own records on each.
  NativeLogRecord logEmitted();
}
