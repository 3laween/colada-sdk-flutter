/// Diagnostic log records emitted by the SDK.
library;

import 'package:meta/meta.dart';

/// Severity of a [ColadaLogRecord].
enum ColadaLogLevel {
  /// Detailed tracing. Emitted only when `ColadaConfig.debug` is `true`.
  debug('debug'),

  /// Notable lifecycle events, such as attribution resolving.
  info('info'),

  /// Something unexpected that the SDK recovered from.
  ///
  /// This is also the level used when a capability is unavailable on the
  /// current platform and was skipped — see `doc/PLATFORM_DIFFERENCES.md`.
  warn('warn'),

  /// The SDK could not complete an operation.
  error('error');

  const ColadaLogLevel(this.wireValue);

  /// Value used when the level crosses the platform channel.
  final String wireValue;

  /// Maps a wire value to a level, falling back to [info] rather than throwing.
  ///
  /// A log record is diagnostic output; failing to parse one must never take
  /// down the stream that carries it.
  static ColadaLogLevel fromWire(String? value) {
    for (final level in ColadaLogLevel.values) {
      if (level.wireValue == value?.toLowerCase()) return level;
    }
    return ColadaLogLevel.info;
  }
}

/// One diagnostic message from the SDK.
///
/// Delivered on `Colada.logs`. Useful for piping SDK diagnostics into your own
/// crash reporter, and for seeing why attribution behaved the way it did.
///
/// Both native SDKs expose a log sink the plugin registers at initialize, so on
/// Android and iOS alike these records come from the native SDK, plus a few the
/// plugin's own bridge emits. Detail is governed by `ColadaConfig.debug` — with
/// it off, only `warn` and `error` are emitted, matching the native SDKs.
@immutable
class ColadaLogRecord {
  /// Creates a log record.
  const ColadaLogRecord({
    required this.level,
    required this.message,
    this.error,
  });

  /// Severity of this record.
  final ColadaLogLevel level;

  /// Human-readable text. Never contains a full tenant key.
  final String message;

  /// Associated error description, when there is one.
  ///
  /// A description rather than the error object: stack traces are not carried
  /// across the platform channel, because they are noisy and can leak internal
  /// type names into an integrator's console.
  final String? error;

  @override
  String toString() =>
      '[${level.name}] $message${error == null ? '' : ' ($error)'}';

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is ColadaLogRecord &&
          other.level == level &&
          other.message == message &&
          other.error == error;

  @override
  int get hashCode => Object.hash(level, message, error);
}
