/// Conversions between the public models and the generated channel DTOs.
///
/// Kept as free functions so they are trivially unit-testable with no channel,
/// no plugin registration and no device. The mapping is the only place the two
/// type families meet: the public models are stable and documented, the
/// generated DTOs may churn with the schema.
library;

import 'attribution.dart';
import 'config.dart';
import 'logging.dart';
import 'messages.g.dart';

/// Converts a public config into its channel representation.
NativeConfig configToNative(ColadaConfig config) => NativeConfig(
      publicTenantKey: config.publicTenantKey,
      debug: config.debug,
      strictMode: config.strictMode,
      automaticDeepLinkForwarding: config.automaticDeepLinkForwarding,
      existingDeviceId: config.existingDeviceId,
    );

/// Converts a channel attribution into the public model.
ColadaAttribution attributionFromNative(NativeAttribution native) =>
    ColadaAttribution(
      matched: native.matched,
      // Parsed with a fallback rather than a strict enum decode: an older
      // plugin must survive the backend adding a new match strategy.
      matchMethod: ColadaMatchMethod.fromWire(native.matchMethod),
      utmSource: native.utmSource,
      utmCampaign: native.utmCampaign,
      utmMedium: native.utmMedium,
      utmContent: native.utmContent,
      utmTerm: native.utmTerm,
      clickId: native.clickId,
      attributionId: native.attributionId,
      tenantKey: native.tenantKey,
      deferredDeepLink: native.deferredDeepLink == null
          ? null
          : deferredDeepLinkFromNative(native.deferredDeepLink!),
      extras: Map<String, Object?>.unmodifiable(native.extras),
    );

/// Converts a channel deferred deep link into the public model.
ColadaDeferredDeepLink deferredDeepLinkFromNative(
  NativeDeferredDeepLink native,
) =>
    ColadaDeferredDeepLink(
      extras: Map<String, String>.unmodifiable(native.extras),
    );

/// Converts a channel log record into the public model.
ColadaLogRecord logRecordFromNative(NativeLogRecord native) => ColadaLogRecord(
      level: ColadaLogLevel.fromWire(native.level),
      message: native.message,
      error: native.error,
    );
