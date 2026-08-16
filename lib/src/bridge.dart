/// The internal seam between the public [Colada] facade and the generated
/// platform channel.
///
/// This exists so the public facade carries **no test-only members**. Tests
/// import this file directly and swap [ColadaBridge.instance] for one built on
/// fakes; integrators only ever see `Colada`.
library;

import 'dart:async';

import 'package:flutter/services.dart';
import 'package:meta/meta.dart';

import 'attribution.dart';
import 'config.dart';
import 'exception_mapper.dart';
import 'exceptions.dart';
import 'logging.dart';
import 'mappers.dart';
import 'messages.g.dart';

/// Owns the channel objects, the stream plumbing and the error translation.
@internal
class ColadaBridge {
  /// Creates a bridge.
  ///
  /// The three sources are injectable so tests can drive the whole facade
  /// without a plugin registration, a device, or a running engine.
  ColadaBridge({
    ColadaHostApi? hostApi,
    Stream<NativeAttribution> Function()? attributionSource,
    Stream<NativeLogRecord> Function()? logSource,
  })  : _hostApi = hostApi ?? ColadaHostApi(),
        _attributionSource = attributionSource ?? attributionResolved,
        _logSource = logSource ?? logEmitted;

  /// The bridge every `Colada` call goes through.
  static ColadaBridge instance = ColadaBridge();

  /// Replaces [instance]. Test-only.
  @visibleForTesting
  static void setInstance(ColadaBridge bridge) {
    instance.dispose();
    instance = bridge;
  }

  /// Restores the real bridge. Test-only.
  @visibleForTesting
  static void resetInstance() {
    instance.dispose();
    instance = ColadaBridge();
  }

  final ColadaHostApi _hostApi;
  final Stream<NativeAttribution> Function() _attributionSource;
  final Stream<NativeLogRecord> Function() _logSource;

  StreamController<ColadaAttribution>? _attributionController;
  StreamSubscription<NativeAttribution>? _attributionSubscription;
  ColadaAttribution? _lastAttribution;

  StreamController<ColadaLogRecord>? _logController;
  StreamSubscription<NativeLogRecord>? _logSubscription;

  // ---------------------------------------------------------------- lifecycle

  /// See `Colada.initialize`.
  Future<void> initialize(ColadaConfig config) => _guard(
        'initialize',
        () async {
          await _hostApi.initialize(configToNative(config));
          // Subscribe only after the native SDK is up, so the first attribution
          // it resolves cannot be missed. Listening earlier would attach to a
          // channel with no handler on the other end.
          _ensureAttributionStarted();
          _ensureLogsStarted();
        },
      );

  /// See `Colada.isInitialized`.
  Future<bool> isInitialized() =>
      _guard('isInitialized', () => _hostApi.isInitialized());

  /// See `Colada.deviceId`.
  Future<String?> deviceId() => _guard('deviceId', () => _hostApi.deviceId());

  // ----------------------------------------------------------------- identity

  /// See `Colada.setUser`.
  Future<void> setUser(String externalUserId) =>
      _guard('setUser', () => _hostApi.setUser(externalUserId));

  /// See `Colada.clearUser`.
  Future<void> clearUser() => _guard('clearUser', () => _hostApi.clearUser());

  // ------------------------------------------------------------------- events

  /// See `Colada.track`.
  Future<void> track(String eventName, Map<String, Object?> metadata) =>
      _guard('track', () => _hostApi.track(eventName, metadata));

  /// See `Colada.flush`.
  Future<void> flush() => _guard('flush', () => _hostApi.flush());

  // -------------------------------------------------------------- attribution

  /// See `Colada.attribution`.
  Future<ColadaAttribution?> currentAttribution() =>
      _guard('attribution', () async {
        final native = await _hostApi.currentAttribution();
        return native == null ? null : attributionFromNative(native);
      });

  /// See `Colada.consumeDeferredDeepLink`.
  Future<ColadaDeferredDeepLink?> consumeDeferredDeepLink() =>
      _guard('consumeDeferredDeepLink', () async {
        final native = await _hostApi.consumeDeferredDeepLink();
        return native == null ? null : deferredDeepLinkFromNative(native);
      });

  /// See `Colada.handleDeepLink`.
  Future<void> handleDeepLink(Uri uri) =>
      _guard('handleDeepLink', () => _hostApi.handleDeepLink(uri.toString()));

  /// See `Colada.attributionStream`.
  ///
  /// Each subscriber gets the most recent result replayed before the live
  /// feed. Attribution typically resolves within a few hundred milliseconds of
  /// `initialize`, usually before any UI is ready to subscribe — without the
  /// replay, deferred deep links would work on a slow network and fail on a
  /// fast one.
  Stream<ColadaAttribution> get attributionStream {
    final controller = _ensureAttributionStarted();
    return _withReplay(_lastAttribution, controller.stream);
  }

  /// See `Colada.logs`.
  ///
  /// Deliberately **not** replayed: a log stream is a running commentary, and
  /// handing a new subscriber one stale line out of context is misleading.
  Stream<ColadaLogRecord> get logs => _ensureLogsStarted().stream;

  // ------------------------------------------------------------------ internal

  StreamController<ColadaAttribution> _ensureAttributionStarted() {
    final existing = _attributionController;
    if (existing != null) return existing;

    final controller = StreamController<ColadaAttribution>.broadcast();
    _attributionController = controller;
    _attributionSubscription = _attributionSource().listen(
      (NativeAttribution native) {
        final mapped = attributionFromNative(native);
        // Cached unconditionally, even with no listeners attached: a broadcast
        // controller drops events when nobody is listening, and the replay
        // above is what makes a late subscriber correct.
        _lastAttribution = mapped;
        if (!controller.isClosed) controller.add(mapped);
      },
      onError: (Object error) {
        if (controller.isClosed) return;
        controller.addError(
          error is PlatformException
              ? mapPlatformException('attributionStream', error)
              : error,
        );
      },
    );
    return controller;
  }

  StreamController<ColadaLogRecord> _ensureLogsStarted() {
    final existing = _logController;
    if (existing != null) return existing;

    final controller = StreamController<ColadaLogRecord>.broadcast();
    _logController = controller;
    _logSubscription = _logSource().listen(
      (NativeLogRecord native) {
        if (!controller.isClosed) controller.add(logRecordFromNative(native));
      },
      // A failure on the diagnostic channel must never become an app-visible
      // error: this is the stream that reports problems, so it cannot be the
      // thing that fails. Dropped silently by design.
      onError: (Object _) {},
    );
    return controller;
  }

  static Stream<T> _withReplay<T>(T? cached, Stream<T> upstream) async* {
    if (cached != null) yield cached;
    yield* upstream;
  }

  /// Runs [body], translating every platform failure into a [ColadaException].
  ///
  /// No call may leak a `PlatformException` or a `MissingPluginException` to
  /// the app: an integrator catching `ColadaException` must catch everything.
  Future<T> _guard<T>(String method, Future<T> Function() body) async {
    try {
      return await body();
    } on PlatformException catch (error) {
      throw mapPlatformException(method, error);
    } on MissingPluginException {
      throw mapMissingPlugin(method);
    }
  }

  /// Releases the stream subscriptions. Test-only; the plugin lives as long as
  /// the app does.
  @visibleForTesting
  void dispose() {
    unawaited(_attributionSubscription?.cancel());
    unawaited(_logSubscription?.cancel());
    unawaited(_attributionController?.close());
    unawaited(_logController?.close());
    _attributionSubscription = null;
    _logSubscription = null;
    _attributionController = null;
    _logController = null;
    _lastAttribution = null;
  }
}
