import 'dart:io';

import 'package:colada_sdk/src/error_codes.dart';
import 'package:flutter_test/flutter_test.dart';

/// The error-code vocabulary is a contract between three languages. Dart owns
/// the canonical list; these tests fail if a native bridge drifts from it.
///
/// Reading the native sources as text is deliberate. There is no way to link
/// Kotlin or Swift constants into a Dart test, and the alternative — trusting
/// three hand-maintained lists to stay in step — is exactly the kind of silent
/// drift that turns a typed exception into a generic one.
void main() {
  group('the code vocabulary', () {
    test('is complete and unique', () {
      expect(
          ColadaErrorCode.values.toSet().length, ColadaErrorCode.values.length);
      expect(ColadaErrorCode.values, everyElement(startsWith('colada/')));
    });
  });

  group('native bridges declare the same codes', () {
    test('Kotlin', () {
      final source = File(
        'android/src/main/kotlin/io/coladaapp/sdk/flutter/ColadaSdkPlugin.kt',
      ).readAsStringSync();
      for (final code in ColadaErrorCode.values) {
        expect(source, contains('"$code"'),
            reason: 'Kotlin ColadaErrorCode is missing $code');
      }
    });

    test('Swift', () {
      final source =
          File('ios/colada_sdk/Sources/colada_sdk/ColadaSdkPlugin.swift')
              .readAsStringSync();
      for (final code in ColadaErrorCode.values) {
        expect(source, contains('"$code"'),
            reason: 'Swift ColadaErrorCode is missing $code');
      }
    });
  });
}
