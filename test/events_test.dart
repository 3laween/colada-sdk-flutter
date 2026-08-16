import 'package:colada_sdk/colada_sdk.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('event wire names', () {
    test('every typed event carries the exact backend name', () {
      // These strings are the contract with the backend. A typo here is a 400
      // in production and nothing at all in a test that checks only the type.
      expect(const CompleteRegistration().eventName, 'CompleteRegistration');
      expect(const Login().eventName, 'Login');
      expect(
        const Purchase(amount: 1, currency: 'SAR', orderId: 'o').eventName,
        'Purchase',
      );
      expect(
          const Subscribe(amount: 1, currency: 'SAR').eventName, 'Subscribe');
      expect(const AddToCart().eventName, 'AddToCart');
      expect(const InitiateCheckout().eventName, 'InitiateCheckout');
      expect(const ViewContent().eventName, 'ViewContent');
      expect(const PlaceAnOrder().eventName, 'PlaceAnOrder');
      expect(const Search().eventName, 'Search');
    });
  });

  group('CompleteRegistration', () {
    test('omits absent contact fields entirely', () {
      expect(const CompleteRegistration().metadata, isEmpty);
    });

    test('includes only the fields that were supplied', () {
      const event = CompleteRegistration(name: 'Amr', phoneNumber: '+9665');
      expect(event.metadata, <String, Object?>{
        'phoneNumber': '+9665',
        'name': 'Amr',
      });
      expect(event.metadata.containsKey('email'), isFalse);
    });

    test('carries extras alongside contact fields', () {
      const event = CompleteRegistration(
        email: 'a@example.com',
        extras: <String, Object?>{'storeId': 'store_789'},
      );
      expect(event.metadata['storeId'], 'store_789');
      expect(event.metadata['email'], 'a@example.com');
    });

    test('a declared field wins over an extras entry of the same name', () {
      // Mirrors the native Android SDK's ordering: extras are spread first, so
      // the typed field always overwrites. Without this, a caller passing both
      // would get whichever the map happened to iterate last.
      const event = CompleteRegistration(
        name: 'declared',
        extras: <String, Object?>{'name': 'from extras'},
      );
      expect(event.metadata['name'], 'declared');
    });
  });

  group('Purchase and Subscribe', () {
    test('carry exactly their declared fields', () {
      expect(
        const Purchase(amount: 49.99, currency: 'SAR', orderId: 'ORD-1')
            .metadata,
        <String, Object?>{
          'amount': 49.99,
          'currency': 'SAR',
          'orderId': 'ORD-1',
        },
      );
      expect(
        const Subscribe(amount: 9.99, currency: 'SAR').metadata,
        <String, Object?>{'amount': 9.99, 'currency': 'SAR'},
      );
    });

    test('reject a non-finite amount', () {
      // NaN and Infinity cannot be represented in JSON and would either crash
      // the channel codec or reach the backend as something meaningless.
      for (final bad in <double>[double.nan, double.infinity]) {
        expect(
          () => Purchase(amount: bad, currency: 'SAR', orderId: 'o').validate(),
          throwsA(isA<ColadaInvalidEventException>()),
          reason: 'amount $bad must be rejected',
        );
      }
    });

    test('reject a blank currency or orderId', () {
      expect(
        () =>
            const Purchase(amount: 1, currency: '  ', orderId: 'o').validate(),
        throwsA(
          isA<ColadaInvalidEventException>()
              .having((e) => e.message, 'message', contains('currency')),
        ),
      );
      expect(
        () =>
            const Purchase(amount: 1, currency: 'SAR', orderId: '').validate(),
        throwsA(
          isA<ColadaInvalidEventException>()
              .having((e) => e.message, 'message', contains('orderId')),
        ),
      );
      expect(
        () => const Subscribe(amount: 1, currency: '').validate(),
        throwsA(isA<ColadaInvalidEventException>()),
      );
    });

    test('accept a well-formed event', () {
      const Purchase(amount: 49.99, currency: 'SAR', orderId: 'ORD-1')
          .validate();
      const Subscribe(amount: 9.99, currency: 'SAR').validate();
    });
  });

  group('RawEvent', () {
    test('carries the exact name given', () {
      expect(const RawEvent(eventName: 'NewBackendEvent').eventName,
          'NewBackendEvent');
    });

    test('refuses Download, which the backend fires itself', () {
      // Making it impossible to express is the whole point; this is the one
      // path that could still get there, so it is closed explicitly.
      expect(
        () => const RawEvent(eventName: 'Download').validate(),
        throwsA(
          isA<ColadaInvalidEventException>()
              .having((e) => e.message, 'message', contains('automatically')),
        ),
      );
    });

    test('refuses a blank name', () {
      expect(
        () => const RawEvent(eventName: '   ').validate(),
        throwsA(isA<ColadaInvalidEventException>()),
      );
    });
  });

  group('metadata validation', () {
    test('accepts every type the platform channel can carry', () {
      const AddToCart(
        extras: <String, Object?>{
          'aString': 'x',
          'anInt': 1,
          'aDouble': 1.5,
          'aBool': true,
          'aNull': null,
          'aList': <Object?>['a', 1, null],
          'aMap': <String, Object?>{'nested': 'value'},
        },
      ).validate();
    });

    test('rejects a value the codec cannot carry, naming the key', () {
      // Without this the failure happens deep inside the codec with an opaque
      // message that does not say which field was at fault.
      expect(
        () => AddToCart(
          extras: <String, Object?>{'when': DateTime(2026)},
        ).validate(),
        throwsA(
          isA<ColadaInvalidEventException>()
              .having((e) => e.message, 'message', contains("['when']"))
              .having((e) => e.message, 'message', contains('DateTime')),
        ),
      );
    });

    test('rejects a bad value nested inside a list', () {
      expect(
        () => AddToCart(
          extras: <String, Object?>{
            'items': <Object?>['ok', DateTime(2026)],
          },
        ).validate(),
        throwsA(
          isA<ColadaInvalidEventException>()
              .having((e) => e.message, 'message', contains('items[1]')),
        ),
      );
    });

    test('rejects a bad value nested inside a map', () {
      expect(
        () => AddToCart(
          extras: <String, Object?>{
            'outer': <String, Object?>{'inner': DateTime(2026)},
          },
        ).validate(),
        throwsA(
          isA<ColadaInvalidEventException>()
              .having((e) => e.message, 'message', contains('outer.inner')),
        ),
      );
    });

    test('rejects a non-String map key', () {
      expect(
        () => const AddToCart(
          extras: <String, Object?>{
            'outer': <Object?, Object?>{1: 'value'},
          },
        ).validate(),
        throwsA(
          isA<ColadaInvalidEventException>()
              .having((e) => e.message, 'message', contains('non-String key')),
        ),
      );
    });

    test('rejects a non-finite number in extras', () {
      expect(
        () => const AddToCart(
          extras: <String, Object?>{'ratio': double.nan},
        ).validate(),
        throwsA(
          isA<ColadaInvalidEventException>()
              .having((e) => e.message, 'message', contains("['ratio']")),
        ),
      );
    });
  });

  group('toMap', () {
    test('produces the shape the bridge sends', () {
      expect(
        const Purchase(amount: 1.5, currency: 'SAR', orderId: 'o').toMap(),
        <String, Object?>{
          'eventName': 'Purchase',
          'metadata': <String, Object?>{
            'amount': 1.5,
            'currency': 'SAR',
            'orderId': 'o',
          },
        },
      );
    });
  });

  group('value semantics', () {
    test('same event, same fields compares equal', () {
      expect(
        const Purchase(amount: 1, currency: 'SAR', orderId: 'o'),
        equals(const Purchase(amount: 1, currency: 'SAR', orderId: 'o')),
      );
    });

    test('different events with identical metadata are not equal', () {
      // Both have empty metadata; only the type distinguishes them, and
      // conflating the two would be a silent mis-report to the ad platform.
      expect(const Login(), isNot(equals(const Search())));
    });
  });
}
