import 'package:colada_sdk/colada_sdk.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('every exception is a ColadaException', () {
    test('so one catch clause covers the whole SDK', () {
      // An integrator writing `on ColadaException` must never be surprised by
      // a platform exception leaking through from the bridge.
      final all = <ColadaException>[
        const ColadaNotInitializedException('track'),
        const ColadaInvalidConfigException('publicTenantKey', 'is bad.'),
        const ColadaInvalidEventException('Purchase', 'is bad.'),
        const ColadaMissingUserException(),
        const ColadaBackendRejectedException(400, 'bad request'),
        const ColadaDeliveryFailedException(3),
        const ColadaNetworkException(),
        const ColadaTokenExpiredException(),
        const ColadaDeviceIdentityUnavailableException(),
        const ColadaTrackingBlockedException(),
        const ColadaUnsupportedException(feature: 'X', platform: 'iOS'),
      ];
      for (final e in all) {
        expect(e, isA<Exception>());
        expect(e.message, isNotEmpty);
        expect(e.toString(), contains(e.runtimeType.toString()));
      }
    });
  });

  group('messages carry the actionable detail', () {
    test('not-initialized names the method that was called too early', () {
      const e = ColadaNotInitializedException('track');
      expect(e.method, 'track');
      expect(e.message, contains('Colada.track'));
      expect(e.message, contains('initialize()'));
    });

    test('invalid config names the offending field', () {
      const e = ColadaInvalidConfigException('publicTenantKey', 'is required.');
      expect(e.fieldName, 'publicTenantKey');
      expect(e.message, 'ColadaConfig.publicTenantKey is required.');
    });

    test('invalid event names the offending event', () {
      const e = ColadaInvalidEventException('Purchase', "needs 'amount'.");
      expect(e.eventName, 'Purchase');
      expect(e.message, "Purchase needs 'amount'.");
    });

    test('backend rejection carries the status and the server message', () {
      const e = ColadaBackendRejectedException(404, 'user not found');
      expect(e.statusCode, 404);
      expect(e.serverMessage, 'user not found');
      expect(e.message, contains('404'));
      expect(e.message, contains('user not found'));
    });

    test('backend rejection reads correctly with no server message', () {
      const e = ColadaBackendRejectedException(401);
      expect(e.serverMessage, isNull);
      expect(e.message, endsWith('401.'));
    });

    test('delivery failure reports the attempt count and that it is retried',
        () {
      const e = ColadaDeliveryFailedException(3);
      expect(e.attempts, 3);
      expect(e.message, contains('3 attempt'));
      expect(e.message, contains('retried'));
    });

    test('unsupported names both the feature and the platform', () {
      const e = ColadaUnsupportedException(
        feature: 'Custom event names',
        platform: 'iOS',
        alternative: 'Use one of the nine typed events.',
      );
      expect(e.feature, 'Custom event names');
      expect(e.platform, 'iOS');
      expect(e.message, contains('Custom event names'));
      expect(e.message, contains('iOS'));
      expect(e.message, contains('nine typed events'));
    });

    test('tracking-blocked says the network is fine, because iOS lies', () {
      // The OS reports this as an offline error. Integrators chase network
      // bugs that do not exist; the message is the fix.
      expect(
        const ColadaTrackingBlockedException().message,
        contains('network is fine'),
      );
    });
  });
}
