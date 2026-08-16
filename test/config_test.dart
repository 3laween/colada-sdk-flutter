import 'package:colada_sdk/colada_sdk.dart';
import 'package:flutter_test/flutter_test.dart';

/// A well-formed key: the `pk_live_` prefix plus exactly 64 hex characters.
/// Obviously fake — never a real tenant key, in tests or anywhere else.
final String validKey = 'pk_live_${'0123456789abcdef' * 4}';

void main() {
  group('ColadaConfig.validate', () {
    test('accepts a well-formed key', () {
      ColadaConfig(publicTenantKey: validKey).validate();
    });

    test('accepts uppercase hex', () {
      // The native Android validator accepts A-F; the iOS plausibility check is
      // lowercase-only, but it is DEBUG-only and non-fatal. Accepting both here
      // matches the platform that actually enforces the rule.
      ColadaConfig(publicTenantKey: 'pk_live_${'0123456789ABCDEF' * 4}')
          .validate();
    });

    test('rejects a blank key', () {
      expect(
        () => const ColadaConfig(publicTenantKey: '   ').validate(),
        throwsA(
          isA<ColadaInvalidConfigException>()
              .having((e) => e.fieldName, 'fieldName', 'publicTenantKey')
              .having((e) => e.message, 'message', contains('blank')),
        ),
      );
    });

    test('rejects a secret key with a message naming the danger', () {
      // Checked before the prefix rule on purpose: a secret key shipped in an
      // app bundle is a live credential leak, not a typo, and the message has
      // to say so rather than reporting a generic prefix mismatch.
      expect(
        () => ColadaConfig(publicTenantKey: 'sk_live_${'a' * 64}').validate(),
        throwsA(
          isA<ColadaInvalidConfigException>()
              .having((e) => e.message, 'message', contains('SECRET key'))
              .having((e) => e.message, 'message', contains('extract it')),
        ),
      );
    });

    test('rejects a wrong prefix', () {
      expect(
        () => ColadaConfig(publicTenantKey: 'pk_test_${'a' * 64}').validate(),
        throwsA(
          isA<ColadaInvalidConfigException>()
              .having((e) => e.message, 'message', contains('pk_live_')),
        ),
      );
    });

    test('rejects a key that is too short, reporting the actual length', () {
      expect(
        () => const ColadaConfig(publicTenantKey: 'pk_live_abc').validate(),
        throwsA(
          isA<ColadaInvalidConfigException>()
              .having((e) => e.message, 'message', contains('had 3')),
        ),
      );
    });

    test('rejects a key that is too long', () {
      expect(
        () => ColadaConfig(publicTenantKey: 'pk_live_${'a' * 65}').validate(),
        throwsA(
          isA<ColadaInvalidConfigException>()
              .having((e) => e.message, 'message', contains('had 65')),
        ),
      );
    });

    test('rejects non-hexadecimal characters at the right length', () {
      expect(
        () => ColadaConfig(publicTenantKey: 'pk_live_${'z' * 64}').validate(),
        throwsA(
          isA<ColadaInvalidConfigException>().having(
            (e) => e.message,
            'message',
            contains('non-hexadecimal'),
          ),
        ),
      );
    });

    test('rejects a blank existingDeviceId but allows it absent or set', () {
      ColadaConfig(publicTenantKey: validKey).validate();
      ColadaConfig(publicTenantKey: validKey, existingDeviceId: 'abc')
          .validate();
      expect(
        () => ColadaConfig(
          publicTenantKey: validKey,
          existingDeviceId: '  ',
        ).validate(),
        throwsA(
          isA<ColadaInvalidConfigException>()
              .having((e) => e.fieldName, 'fieldName', 'existingDeviceId'),
        ),
      );
    });
  });

  group('ColadaConfig defaults', () {
    test('only the tenant key is required', () {
      final config = ColadaConfig(publicTenantKey: validKey);
      expect(config.debug, isFalse);
      expect(config.strictMode, isFalse);
      expect(config.existingDeviceId, isNull);
      // Automatic forwarding is on by default: the integrator gets working
      // deep-link attribution without touching MainActivity or AppDelegate.
      expect(config.automaticDeepLinkForwarding, isTrue);
    });
  });

  group('ColadaConfig.redactKey', () {
    test('keeps the prefix and four characters', () {
      expect(ColadaConfig.redactKey(validKey), 'pk_live_0123…');
    });

    test('fully masks a value too short to redact meaningfully', () {
      expect(ColadaConfig.redactKey('abc'), '***');
    });

    test('does not overflow on a value shorter than the visible window', () {
      expect(ColadaConfig.redactKey('pk_live'), 'pk_live…');
    });
  });

  group('ColadaConfig.toString', () {
    test('never contains the key in full', () {
      final config = ColadaConfig(publicTenantKey: validKey);
      // Logs get pasted into bug reports and chat. This is the guard.
      expect(config.toString(), isNot(contains(validKey)));
      expect(config.toString(), contains('pk_live_0123…'));
    });
  });

  group('ColadaConfig value semantics', () {
    test('equal configs compare equal and hash alike', () {
      final a = ColadaConfig(publicTenantKey: validKey, debug: true);
      final b = ColadaConfig(publicTenantKey: validKey, debug: true);
      expect(a, equals(b));
      expect(a.hashCode, equals(b.hashCode));
    });

    test('copyWith replaces only what it is given', () {
      final base = ColadaConfig(publicTenantKey: validKey);
      final copy = base.copyWith(strictMode: true);
      expect(copy.strictMode, isTrue);
      expect(copy.publicTenantKey, validKey);
      expect(copy.automaticDeepLinkForwarding, isTrue);
    });
  });
}
