import 'package:colada_sdk/colada_sdk.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('ColadaLogLevel.fromWire', () {
    test('maps every known level', () {
      expect(ColadaLogLevel.fromWire('debug'), ColadaLogLevel.debug);
      expect(ColadaLogLevel.fromWire('info'), ColadaLogLevel.info);
      expect(ColadaLogLevel.fromWire('warn'), ColadaLogLevel.warn);
      expect(ColadaLogLevel.fromWire('error'), ColadaLogLevel.error);
    });

    test('is case-insensitive', () {
      expect(ColadaLogLevel.fromWire('ERROR'), ColadaLogLevel.error);
    });

    test('falls back to info rather than throwing', () {
      // A log record is diagnostic output. Failing to parse one must never
      // take down the stream that carries it.
      expect(ColadaLogLevel.fromWire('verbose'), ColadaLogLevel.info);
      expect(ColadaLogLevel.fromWire(null), ColadaLogLevel.info);
    });
  });

  group('ColadaLogRecord', () {
    test('reads as a log line', () {
      const record = ColadaLogRecord(
        level: ColadaLogLevel.warn,
        message: 'clipboard unavailable',
      );
      expect(record.toString(), '[warn] clipboard unavailable');
    });

    test('appends the error when there is one', () {
      const record = ColadaLogRecord(
        level: ColadaLogLevel.error,
        message: 'handshake failed',
        error: 'SocketException',
      );
      expect(record.toString(), contains('handshake failed'));
      expect(record.toString(), contains('SocketException'));
    });

    test('compares by value', () {
      const a = ColadaLogRecord(level: ColadaLogLevel.info, message: 'x');
      const b = ColadaLogRecord(level: ColadaLogLevel.info, message: 'x');
      expect(a, equals(b));
      expect(a.hashCode, equals(b.hashCode));
    });
  });
}
