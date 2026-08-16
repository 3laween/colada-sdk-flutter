import 'package:colada_sdk/colada_sdk.dart';
import 'package:colada_sdk/src/attribution.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('ColadaMatchMethod.fromWire', () {
    test('maps every known backend value', () {
      expect(ColadaMatchMethod.fromWire('direct_deeplink'),
          ColadaMatchMethod.directDeeplink);
      expect(ColadaMatchMethod.fromWire('play_referrer'),
          ColadaMatchMethod.playReferrer);
      expect(
          ColadaMatchMethod.fromWire('clipboard'), ColadaMatchMethod.clipboard);
      expect(ColadaMatchMethod.fromWire('probabilistic'),
          ColadaMatchMethod.probabilistic);
      expect(ColadaMatchMethod.fromWire('none'), ColadaMatchMethod.none);
    });

    test('is case-insensitive', () {
      expect(ColadaMatchMethod.fromWire('PLAY_REFERRER'),
          ColadaMatchMethod.playReferrer);
    });

    test('falls back to unknown rather than throwing', () {
      // This is what lets an older SDK in the field survive the backend adding
      // a new strategy. Throwing here would break every app that has not
      // upgraded, for a value they do not even need to understand.
      expect(ColadaMatchMethod.fromWire('quantum_entanglement'),
          ColadaMatchMethod.unknown);
      expect(ColadaMatchMethod.fromWire(null), ColadaMatchMethod.unknown);
      expect(ColadaMatchMethod.fromWire(''), ColadaMatchMethod.unknown);
    });
  });

  group('ColadaDeferredDeepLink.hasDestination', () {
    test('is false when there is genuinely nowhere to go', () {
      expect(const ColadaDeferredDeepLink().hasDestination, isFalse);
      // isCoffeeSubscription alone is a flag about the destination, not a
      // destination — navigating on it would send the user nowhere.
      expect(
        const ColadaDeferredDeepLink(isCoffeeSubscription: true).hasDestination,
        isFalse,
      );
    });

    test('is true for any real destination', () {
      expect(
        const ColadaDeferredDeepLink(storeId: 's').hasDestination,
        isTrue,
      );
      expect(
        const ColadaDeferredDeepLink(menuItemId: 'm').hasDestination,
        isTrue,
      );
      expect(
        const ColadaDeferredDeepLink(extras: <String, String>{'k': 'v'})
            .hasDestination,
        isTrue,
      );
    });
  });

  group('ColadaAttribution.unmatched', () {
    test('is an organic install, not an error state', () {
      const result = ColadaAttribution.unmatched();
      expect(result.matched, isFalse);
      expect(result.matchMethod, ColadaMatchMethod.none);
      expect(result.deferredDeepLink, isNull);
      expect(result.extras, isEmpty);
    });
  });

  group('round-trips', () {
    test('a full attribution survives toMap/fromMap unchanged', () {
      const original = ColadaAttribution(
        matched: true,
        matchMethod: ColadaMatchMethod.playReferrer,
        utmSource: 'tiktok',
        utmCampaign: 'summer',
        utmMedium: 'paid_social',
        utmContent: 'video_a',
        utmTerm: 'coffee',
        clickId: 'ttclid_123',
        attributionId: 'attr_1',
        tenantKey: 'colada',
        deferredDeepLink: ColadaDeferredDeepLink(
          storeId: 'store_1',
          menuItemId: 'item_2',
          isCoffeeSubscription: true,
          extras: <String, String>{'ref': 'abc'},
        ),
        extras: <String, Object?>{'asn': 12345, 'osVersion': '17.0'},
      );

      expect(ColadaAttribution.fromMap(original.toMap()), equals(original));
    });

    test('an unmatched attribution survives the round trip', () {
      const original = ColadaAttribution.unmatched();
      expect(ColadaAttribution.fromMap(original.toMap()), equals(original));
    });

    test('a deferred deep link survives on its own', () {
      const original = ColadaDeferredDeepLink(
        storeId: 'store_1',
        extras: <String, String>{'a': 'b'},
      );
      expect(
        ColadaDeferredDeepLink.fromMap(original.toMap()),
        equals(original),
      );
    });
  });

  group('fromMap tolerance', () {
    test('an empty map yields an unmatched result rather than throwing', () {
      // The bridge must never crash an app because the backend omitted a
      // field. Absence degrades to "not matched", which is a normal outcome.
      final result = ColadaAttribution.fromMap(const <String, Object?>{});
      expect(result.matched, isFalse);
      expect(result.matchMethod, ColadaMatchMethod.unknown);
      expect(result.deferredDeepLink, isNull);
      expect(result.extras, isEmpty);
    });

    test('an unknown matchMethod string degrades to unknown', () {
      final result = ColadaAttribution.fromMap(
        const <String, Object?>{'matched': true, 'matchMethod': 'brand_new'},
      );
      expect(result.matched, isTrue);
      expect(result.matchMethod, ColadaMatchMethod.unknown);
    });

    test('a loosely typed channel map is coerced, not rejected', () {
      // The platform channel hands back Map<Object?, Object?>, not
      // Map<String, Object?>. A naive cast would throw on every real payload.
      final result = ColadaAttribution.fromMap(<String, Object?>{
        'matched': true,
        'deferredDeepLink': <Object?, Object?>{'storeId': 'store_1'},
        'extras': <Object?, Object?>{'asn': 42},
      });
      expect(result.deferredDeepLink?.storeId, 'store_1');
      expect(result.extras['asn'], 42);
    });
  });

  group('toString', () {
    test('names the fields worth seeing in a log', () {
      const result = ColadaAttribution(
        matched: true,
        matchMethod: ColadaMatchMethod.clipboard,
        utmCampaign: 'summer',
      );
      expect(result.toString(), contains('matched: true'));
      expect(result.toString(), contains('clipboard'));
      expect(result.toString(), contains('summer'));
    });
  });
}
