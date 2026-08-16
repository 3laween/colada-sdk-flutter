import 'dart:async';

import 'package:colada_sdk/colada_sdk.dart';
import 'package:colada_sdk/src/bridge.dart';
import 'package:colada_sdk/src/error_codes.dart';
import 'package:colada_sdk/src/messages.g.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'config_test.dart' show validKey;
import 'fake_host_api.dart';

void main() {
  late FakeColadaHostApi host;
  late StreamController<NativeAttribution> attribution;
  late StreamController<NativeLogRecord> logs;

  setUp(() {
    host = FakeColadaHostApi();
    attribution = StreamController<NativeAttribution>.broadcast();
    logs = StreamController<NativeLogRecord>.broadcast();
    ColadaBridge.setInstance(
      ColadaBridge(
        hostApi: host,
        attributionSource: () => attribution.stream,
        logSource: () => logs.stream,
      ),
    );
  });

  tearDown(() async {
    ColadaBridge.resetInstance();
    await attribution.close();
    await logs.close();
  });

  group('calls reach the host API', () {
    test('initialize passes the mapped config through', () async {
      await Colada.initialize(
        ColadaConfig(
          publicTenantKey: validKey,
          debug: true,
          strictMode: true,
          existingDeviceId: 'legacy-1',
          automaticDeepLinkForwarding: false,
        ),
      );
      final config = host.lastConfig!;
      expect(config.publicTenantKey, validKey);
      expect(config.debug, isTrue);
      expect(config.strictMode, isTrue);
      expect(config.existingDeviceId, 'legacy-1');
      expect(config.automaticDeepLinkForwarding, isFalse);
    });

    test('identity and lifecycle calls forward their arguments', () async {
      await Colada.setUser('user_1');
      await Colada.clearUser();
      await Colada.flush();
      await Colada.handleDeepLink(
          Uri.parse('https://a.example/x?utm_source=b'));
      expect(host.calls, <String>[
        'setUser(user_1)',
        'clearUser()',
        'flush()',
        'handleDeepLink(https://a.example/x?utm_source=b)',
      ]);
    });

    test('track crosses as the wire name plus a flat metadata map', () async {
      // This is the shape the native Android SDK's own track(name, map)
      // overload was built to receive, and the shape the iOS bridge decomposes.
      await Colada.track(
        const Purchase(amount: 49.99, currency: 'SAR', orderId: 'ORD-1'),
      );
      expect(
        host.calls.single,
        'track(Purchase, {amount: 49.99, currency: SAR, orderId: ORD-1})',
      );
    });

    test('deviceId and isInitialized return the host values', () async {
      host
        ..deviceIdValue = 'abc-123'
        ..initializedValue = true;
      expect(await Colada.deviceId, 'abc-123');
      expect(await Colada.isInitialized, isTrue);
    });
  });

  group('models cross the boundary intact', () {
    test('an attribution is mapped field for field', () async {
      host.attributionValue = nativeAttribution(
        utmCampaign: 'summer',
        deferredDeepLink: nativeDeepLink(storeId: 'store_9'),
        extras: <String, Object?>{'asn': 42},
      );
      final result = (await Colada.attribution)!;
      expect(result.matched, isTrue);
      expect(result.matchMethod, ColadaMatchMethod.playReferrer);
      expect(result.utmCampaign, 'summer');
      expect(result.deferredDeepLink?.storeId, 'store_9');
      expect(result.extras['asn'], 42);
    });

    test('an unknown matchMethod degrades instead of throwing', () async {
      // The contract that lets an old plugin survive a new backend strategy.
      host.attributionValue = nativeAttribution(matchMethod: 'brand_new');
      expect(
          (await Colada.attribution)!.matchMethod, ColadaMatchMethod.unknown);
    });

    test('a null attribution stays null', () async {
      host.attributionValue = null;
      expect(await Colada.attribution, isNull);
    });

    test('the deferred deep link is consumed exactly once', () async {
      host.deferredDeepLinkValue = nativeDeepLink(storeId: 'store_1');
      expect((await Colada.consumeDeferredDeepLink())?.storeId, 'store_1');
      expect(await Colada.consumeDeferredDeepLink(), isNull);
    });
  });

  group('errors become typed Colada exceptions', () {
    Future<void> expectMapped(
      PlatformException raised,
      Matcher matcher,
    ) async {
      host.nextError = raised;
      await expectLater(Colada.flush(), throwsA(matcher));
    }

    test('each code maps to its exception', () async {
      await expectMapped(
        PlatformException(code: ColadaErrorCode.missingUser),
        isA<ColadaMissingUserException>(),
      );
      await expectMapped(
        PlatformException(code: ColadaErrorCode.tokenExpired),
        isA<ColadaTokenExpiredException>(),
      );
      await expectMapped(
        PlatformException(code: ColadaErrorCode.trackingBlocked),
        isA<ColadaTrackingBlockedException>(),
      );
      await expectMapped(
        PlatformException(code: ColadaErrorCode.deviceIdentityUnavailable),
        isA<ColadaDeviceIdentityUnavailableException>(),
      );
      await expectMapped(
        PlatformException(code: ColadaErrorCode.network, message: 'offline'),
        isA<ColadaNetworkException>(),
      );
      await expectMapped(
        PlatformException(code: ColadaErrorCode.notInitialized),
        isA<ColadaNotInitializedException>()
            .having((e) => e.method, 'method', 'flush'),
      );
    });

    test('structured details survive the crossing', () async {
      await expectMapped(
        PlatformException(
          code: ColadaErrorCode.backendRejected,
          details: <Object?, Object?>{
            'statusCode': 404,
            'serverMessage': 'user not found',
          },
        ),
        isA<ColadaBackendRejectedException>()
            .having((e) => e.statusCode, 'statusCode', 404)
            .having((e) => e.serverMessage, 'serverMessage', 'user not found'),
      );
      await expectMapped(
        PlatformException(
          code: ColadaErrorCode.deliveryFailed,
          details: <Object?, Object?>{'attempts': 3},
        ),
        isA<ColadaDeliveryFailedException>()
            .having((e) => e.attempts, 'attempts', 3),
      );
      await expectMapped(
        PlatformException(
          code: ColadaErrorCode.unsupported,
          details: <Object?, Object?>{
            'feature': 'Custom event names',
            'platform': 'iOS',
          },
        ),
        isA<ColadaUnsupportedException>()
            .having((e) => e.feature, 'feature', 'Custom event names')
            .having((e) => e.platform, 'platform', 'iOS'),
      );
    });

    test('an unrecognised code still yields a ColadaException', () async {
      // A native bridge newer than this Dart version must never leak a raw
      // PlatformException — one catch clause has to cover everything.
      await expectMapped(
        PlatformException(code: 'colada/from-the-future', message: 'hello'),
        isA<ColadaException>(),
      );
    });

    test('a missing plugin reports an unsupported platform', () async {
      // What an app sees on web or desktop. Reporting it as a network failure
      // would send people debugging connectivity that was never involved.
      host.throwMissingPlugin = true;
      await expectLater(
        Colada.flush(),
        throwsA(
          isA<ColadaUnsupportedException>()
              .having((e) => e.message, 'message', contains('Android and iOS')),
        ),
      );
    });

    test('no call leaks a raw PlatformException', () async {
      for (final code in ColadaErrorCode.values) {
        host.nextError = PlatformException(code: code);
        await expectLater(
          Colada.flush(),
          throwsA(isA<ColadaException>()),
          reason: 'code $code must map to a ColadaException',
        );
      }
    });
  });

  group('attributionStream', () {
    test('delivers results as they resolve', () async {
      final seen = <ColadaAttribution>[];
      final sub = Colada.attributionStream.listen(seen.add);
      attribution.add(nativeAttribution(utmCampaign: 'first'));
      await pumpEventQueue();
      expect(seen.single.utmCampaign, 'first');
      await sub.cancel();
    });

    test('replays the latest result to a late subscriber', () async {
      // The behaviour that stops deferred deep links from working on a slow
      // network and failing on a fast one. initialize() first, because that is
      // what subscribes the bridge to the native feed in production — without
      // it the bridge is not listening and the result is genuinely lost.
      await Colada.initialize(ColadaConfig(publicTenantKey: validKey));
      attribution.add(nativeAttribution(utmCampaign: 'resolved-early'));
      await pumpEventQueue();

      final seen = <ColadaAttribution>[];
      final sub = Colada.attributionStream.listen(seen.add);
      await pumpEventQueue();

      expect(seen.single.utmCampaign, 'resolved-early');
      await sub.cancel();
    });

    test('replays even when nobody was listening at the time', () async {
      // A broadcast controller drops events with no listeners; the cache is
      // what makes the replay correct rather than merely likely.
      expect(Colada.attributionStream, isNotNull);
      attribution.add(nativeAttribution(utmCampaign: 'unheard'));
      await pumpEventQueue();

      final seen = <ColadaAttribution>[];
      final sub = Colada.attributionStream.listen(seen.add);
      await pumpEventQueue();
      expect(seen.single.utmCampaign, 'unheard');
      await sub.cancel();
    });

    test('supports several concurrent listeners', () async {
      final a = <ColadaAttribution>[];
      final b = <ColadaAttribution>[];
      final subA = Colada.attributionStream.listen(a.add);
      final subB = Colada.attributionStream.listen(b.add);
      attribution.add(nativeAttribution(utmCampaign: 'shared'));
      await pumpEventQueue();
      expect(a.single.utmCampaign, 'shared');
      expect(b.single.utmCampaign, 'shared');
      await subA.cancel();
      await subB.cancel();
    });

    test('a channel error surfaces as a typed exception', () async {
      final errors = <Object>[];
      final sub = Colada.attributionStream.listen(
        (_) {},
        onError: errors.add,
      );
      attribution.addError(
        PlatformException(code: ColadaErrorCode.network, message: 'down'),
      );
      await pumpEventQueue();
      expect(errors.single, isA<ColadaNetworkException>());
      await sub.cancel();
    });
  });

  group('logs', () {
    test('delivers records', () async {
      final seen = <ColadaLogRecord>[];
      final sub = Colada.logs.listen(seen.add);
      logs.add(NativeLogRecord(level: 'warn', message: 'clipboard empty'));
      await pumpEventQueue();
      expect(seen.single.level, ColadaLogLevel.warn);
      expect(seen.single.message, 'clipboard empty');
      await sub.cancel();
    });

    test('does not replay, unlike attribution', () async {
      // A log stream is a running commentary; handing a new subscriber one
      // stale line out of context is misleading.
      logs.add(NativeLogRecord(level: 'info', message: 'old news'));
      await pumpEventQueue();

      final seen = <ColadaLogRecord>[];
      final sub = Colada.logs.listen(seen.add);
      await pumpEventQueue();
      expect(seen, isEmpty);
      await sub.cancel();
    });

    test('an error on the diagnostic channel is swallowed', () async {
      // This is the stream that reports problems; it cannot be the thing that
      // fails and takes an app down.
      final errors = <Object>[];
      final sub = Colada.logs.listen((_) {}, onError: errors.add);
      logs.addError(PlatformException(code: 'boom'));
      await pumpEventQueue();
      expect(errors, isEmpty);
      await sub.cancel();
    });
  });

  group('validation still runs before the channel', () {
    test('a bad config never reaches the host', () async {
      await expectLater(
        Colada.initialize(const ColadaConfig(publicTenantKey: 'nope')),
        throwsA(isA<ColadaInvalidConfigException>()),
      );
      expect(host.calls, isEmpty);
    });

    test('a malformed event never reaches the host', () async {
      await expectLater(
        Colada.track(const Purchase(amount: 1, currency: '', orderId: 'o')),
        throwsA(isA<ColadaInvalidEventException>()),
      );
      expect(host.calls, isEmpty);
    });

    test('a blank user id never reaches the host', () async {
      await expectLater(
        Colada.setUser('  '),
        throwsA(isA<ColadaInvalidConfigException>()),
      );
      expect(host.calls, isEmpty);
    });
  });
}
