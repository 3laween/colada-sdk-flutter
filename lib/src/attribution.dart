/// Attribution results and deferred deep links.
library;

import 'package:meta/meta.dart';

/// Which strategy resolved an attribution, with the accuracy Colada's backend
/// reports for each.
///
/// Useful for diagnosing why a campaign looks under-attributed.
enum ColadaMatchMethod {
  /// Parameters read straight off the deep link. 100% accurate.
  directDeeplink('direct_deeplink'),

  /// Google Play Install Referrer. 100% accurate. Android only.
  playReferrer('play_referrer'),

  /// Click id recovered from the system clipboard. ~95% accurate.
  clipboard('clipboard'),

  /// IP + ASN + OS version + screen fingerprint. 60–70% accurate.
  probabilistic('probabilistic'),

  /// No match — an organic install.
  none('none'),

  /// The backend reported a strategy this SDK version does not know about.
  ///
  /// Never treat this as an error. It exists so an older SDK in the field
  /// degrades gracefully when the backend adds a strategy, instead of failing.
  unknown('unknown');

  const ColadaMatchMethod(this.wireValue);

  /// Value as sent by the backend.
  final String wireValue;

  /// Maps a backend value, falling back to [unknown] rather than throwing.
  static ColadaMatchMethod fromWire(String? value) {
    if (value == null) return ColadaMatchMethod.unknown;
    final lowered = value.toLowerCase();
    for (final method in ColadaMatchMethod.values) {
      if (method.wireValue == lowered) return method;
    }
    return ColadaMatchMethod.unknown;
  }
}

/// Where to send a user on first open, when the campaign that drove their
/// install specified a destination.
///
/// This is Deferred Deep Linking: the user tapped an ad for a specific store or
/// item, did not have the app, installed it, and should land on that page
/// rather than your home screen. It is the part of attribution users notice.
///
/// Retrieve it with `Colada.consumeDeferredDeepLink()`, which returns it
/// exactly once — navigating a returning user to a campaign page on their tenth
/// launch is a bug, not a feature.
@immutable
class ColadaDeferredDeepLink {
  /// Creates a deferred deep link target.
  const ColadaDeferredDeepLink({
    this.extras = const <String, String>{},
  });

  /// Builds a target from its channel representation.
  @internal
  factory ColadaDeferredDeepLink.fromMap(Map<String, Object?> map) {
    final rawExtras = map['extras'];
    return ColadaDeferredDeepLink(
      extras: rawExtras is Map
          ? <String, String>{
              for (final entry in rawExtras.entries)
                '${entry.key}': '${entry.value}',
            }
          : const <String, String>{},
    );
  }

  /// The destination, as a single string map — the only surface for it.
  ///
  /// Colada's own fields appear here under the keys `storeId`, `menuItemId` and
  /// `isCoffeeSubscription` (the last as `'true'`/`'false'`) when the campaign
  /// carried them, alongside any tenant-specific destination fields. There are
  /// no typed destination properties anymore — read `extras['storeId']`. Both
  /// platforms populate this identically for the same campaign.
  final Map<String, String> extras;

  /// True when there is genuinely somewhere to navigate.
  ///
  /// Check this before navigating: a link can resolve with no destination at
  /// all, in which case the correct behaviour is to leave the user where they
  /// are. The coffee-subscription flag alone is NOT a destination — it
  /// qualifies one — so `isCoffeeSubscription` is the one key that does not
  /// count; any other key does.
  bool get hasDestination =>
      extras.keys.any((String key) => key != 'isCoffeeSubscription');

  /// Flat representation, for forwarding into your own analytics or logs.
  Map<String, Object?> toMap() => <String, Object?>{
        'extras': extras,
      };

  @override
  String toString() => 'ColadaDeferredDeepLink(extras: $extras)';

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is ColadaDeferredDeepLink && _mapEquals(other.extras, extras);

  @override
  int get hashCode => Object.hashAllUnordered(
        extras.entries.map((MapEntry<String, String> e) => (e.key, e.value)),
      );
}

/// The campaign Colada resolved for this install or re-engagement.
///
/// Delivered on `Colada.attributionStream` and readable at any time from
/// `Colada.attribution`.
///
/// [matched] being `false` is a normal outcome, not an error — it means the user
/// installed organically, without clicking an ad.
@immutable
class ColadaAttribution {
  /// Creates an attribution result.
  const ColadaAttribution({
    required this.matched,
    required this.matchMethod,
    this.utmSource,
    this.utmCampaign,
    this.utmMedium,
    this.utmContent,
    this.utmTerm,
    this.clickId,
    this.attributionId,
    this.tenantKey,
    this.deferredDeepLink,
    this.extras = const <String, Object?>{},
  });

  /// An unresolved result — an organic install, or attribution not yet run.
  const ColadaAttribution.unmatched()
      : matched = false,
        matchMethod = ColadaMatchMethod.none,
        utmSource = null,
        utmCampaign = null,
        utmMedium = null,
        utmContent = null,
        utmTerm = null,
        clickId = null,
        attributionId = null,
        tenantKey = null,
        deferredDeepLink = null,
        extras = const <String, Object?>{};

  /// Builds a result from its channel representation.
  @internal
  factory ColadaAttribution.fromMap(Map<String, Object?> map) {
    final rawDeepLink = map['deferredDeepLink'];
    final rawExtras = map['extras'];
    return ColadaAttribution(
      matched: map['matched'] as bool? ?? false,
      matchMethod: ColadaMatchMethod.fromWire(map['matchMethod'] as String?),
      utmSource: map['utmSource'] as String?,
      utmCampaign: map['utmCampaign'] as String?,
      utmMedium: map['utmMedium'] as String?,
      utmContent: map['utmContent'] as String?,
      utmTerm: map['utmTerm'] as String?,
      clickId: map['clickId'] as String?,
      attributionId: map['attributionId'] as String?,
      tenantKey: map['tenantKey'] as String?,
      deferredDeepLink: rawDeepLink is Map
          ? ColadaDeferredDeepLink.fromMap(
              <String, Object?>{
                for (final entry in rawDeepLink.entries)
                  '${entry.key}': entry.value,
              },
            )
          : null,
      extras: rawExtras is Map
          ? <String, Object?>{
              for (final entry in rawExtras.entries)
                '${entry.key}': entry.value,
            }
          : const <String, Object?>{},
    );
  }

  /// Whether attribution resolved to a campaign.
  ///
  /// `false` is an ordinary organic install, not a failure.
  final bool matched;

  /// How it resolved. See [ColadaMatchMethod] for accuracy per strategy.
  final ColadaMatchMethod matchMethod;

  /// Ad platform that drove the install, e.g. `instagram`, `tiktok`.
  final String? utmSource;

  /// Campaign name.
  final String? utmCampaign;

  /// Channel type, e.g. `paid_social`, `cpc`.
  final String? utmMedium;

  /// Ad variant / creative identifier.
  final String? utmContent;

  /// Keyword, for paid search.
  final String? utmTerm;

  /// Ad-platform click identifier (`fbclid`, `ttclid`, `gclid` or `sccid`).
  final String? clickId;

  /// Colada's internal record id.
  ///
  /// Useful when reporting a problem to Colada support; you are not required to
  /// do anything with it.
  final String? attributionId;

  /// Tenant this install belongs to.
  final String? tenantKey;

  /// Where to send the user on first open, if the campaign specified a
  /// destination. `null` when there is nothing to navigate to.
  ///
  /// Prefer `Colada.consumeDeferredDeepLink()` for navigation — it returns the
  /// target exactly once, whereas this field is readable on every result and
  /// would re-navigate a returning user.
  final ColadaDeferredDeepLink? deferredDeepLink;

  /// The campaign destination and any tenant params, as a string map.
  ///
  /// The same map [deferredDeepLink] exposes: `storeId`, `menuItemId` and
  /// `isCoffeeSubscription` appear here under those keys when the campaign
  /// carried them, plus any tenant-specific fields, so a backend addition is
  /// readable without upgrading the SDK. Populated identically on both
  /// platforms for the same campaign. (Typed `Object?` for API stability; the
  /// values are strings.)
  final Map<String, Object?> extras;

  /// Flat representation, for forwarding into your own analytics or logs.
  Map<String, Object?> toMap() => <String, Object?>{
        'matched': matched,
        'matchMethod': matchMethod.wireValue,
        'utmSource': utmSource,
        'utmCampaign': utmCampaign,
        'utmMedium': utmMedium,
        'utmContent': utmContent,
        'utmTerm': utmTerm,
        'clickId': clickId,
        'attributionId': attributionId,
        'tenantKey': tenantKey,
        'deferredDeepLink': deferredDeepLink?.toMap(),
        'extras': extras,
      };

  @override
  String toString() => 'ColadaAttribution(matched: $matched, '
      'matchMethod: ${matchMethod.name}, utmSource: $utmSource, '
      'utmCampaign: $utmCampaign, deferredDeepLink: $deferredDeepLink)';

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is ColadaAttribution &&
          other.matched == matched &&
          other.matchMethod == matchMethod &&
          other.utmSource == utmSource &&
          other.utmCampaign == utmCampaign &&
          other.utmMedium == utmMedium &&
          other.utmContent == utmContent &&
          other.utmTerm == utmTerm &&
          other.clickId == clickId &&
          other.attributionId == attributionId &&
          other.tenantKey == tenantKey &&
          other.deferredDeepLink == deferredDeepLink &&
          _mapEquals(other.extras, extras);

  @override
  int get hashCode => Object.hash(
        matched,
        matchMethod,
        utmSource,
        utmCampaign,
        utmMedium,
        utmContent,
        utmTerm,
        clickId,
        attributionId,
        tenantKey,
        deferredDeepLink,
        Object.hashAllUnordered(
          extras.entries.map((MapEntry<String, Object?> e) => (e.key, e.value)),
        ),
      );
}

/// Shallow map equality. Values are compared with `==`.
bool _mapEquals<K, V>(Map<K, V> a, Map<K, V> b) {
  if (identical(a, b)) return true;
  if (a.length != b.length) return false;
  for (final entry in a.entries) {
    if (!b.containsKey(entry.key) || b[entry.key] != entry.value) return false;
  }
  return true;
}
