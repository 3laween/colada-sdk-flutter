// The two pigeonVar_ getters below satisfy the generated ColadaHostApi
// contract; the names are Pigeon's, so the style lint is waived here.
// ignore_for_file: non_constant_identifier_names

import 'dart:async';

import 'package:colada_sdk/src/messages.g.dart';
import 'package:flutter/services.dart';

/// A [ColadaHostApi] that records calls and answers from memory.
///
/// Lets the whole facade be driven without a plugin registration, a device, or
/// a running engine — so every Dart-side behaviour (argument marshalling, error
/// translation, stream replay) is tested where it is cheap to test.
class FakeColadaHostApi implements ColadaHostApi {
  /// Every call made, in order, as `method(arg, ...)`.
  final List<String> calls = <String>[];

  /// Raised by the next call to any method, if set.
  PlatformException? nextError;

  /// Thrown instead of [nextError] when set — for the no-plugin case.
  bool throwMissingPlugin = false;

  /// Returned by [deviceId].
  String? deviceIdValue = 'device-1';

  /// Returned by [isInitialized].
  bool initializedValue = false;

  /// Returned by [currentAttribution].
  NativeAttribution? attributionValue;

  /// Returned by [consumeDeferredDeepLink]; cleared after the first read, the
  /// way both native SDKs behave.
  NativeDeferredDeepLink? deferredDeepLinkValue;

  /// The config passed to [initialize], for asserting the mapping.
  NativeConfig? lastConfig;

  // The generated ColadaHostApi is a concrete class rather than an interface,
  // so `implements` must satisfy its channel fields too. Nothing here uses
  // them — every method below answers from memory without touching a channel.
  @override
  BinaryMessenger? get pigeonVar_binaryMessenger => null;

  @override
  String get pigeonVar_messageChannelSuffix => '';

  void _record(String call) {
    calls.add(call);
    if (throwMissingPlugin) {
      throw MissingPluginException('no implementation');
    }
    final error = nextError;
    if (error != null) {
      nextError = null;
      throw error;
    }
  }

  @override
  Future<void> initialize(NativeConfig config) async {
    _record('initialize(${config.publicTenantKey})');
    lastConfig = config;
    initializedValue = true;
  }

  @override
  Future<bool> isInitialized() async {
    _record('isInitialized()');
    return initializedValue;
  }

  @override
  Future<String?> deviceId() async {
    _record('deviceId()');
    return deviceIdValue;
  }

  @override
  Future<void> setUser(String externalUserId) async {
    _record('setUser($externalUserId)');
  }

  @override
  Future<void> clearUser() async {
    _record('clearUser()');
  }

  @override
  Future<void> track(String eventName, Map<String, Object?> metadata) async {
    _record('track($eventName, $metadata)');
  }

  @override
  Future<void> flush() async {
    _record('flush()');
  }

  @override
  Future<NativeAttribution?> currentAttribution() async {
    _record('currentAttribution()');
    return attributionValue;
  }

  @override
  Future<NativeDeferredDeepLink?> consumeDeferredDeepLink() async {
    _record('consumeDeferredDeepLink()');
    final value = deferredDeepLinkValue;
    deferredDeepLinkValue = null;
    return value;
  }

  @override
  Future<void> handleDeepLink(String url) async {
    _record('handleDeepLink($url)');
  }
}

/// Builds a channel attribution with sensible defaults.
NativeAttribution nativeAttribution({
  bool matched = true,
  String? matchMethod = 'play_referrer',
  String? utmCampaign,
  NativeDeferredDeepLink? deferredDeepLink,
  Map<String, Object?> extras = const <String, Object?>{},
}) =>
    NativeAttribution(
      matched: matched,
      matchMethod: matchMethod,
      utmCampaign: utmCampaign,
      deferredDeepLink: deferredDeepLink,
      extras: extras,
    );

/// Builds a channel deferred deep link with sensible defaults.
NativeDeferredDeepLink nativeDeepLink({
  String? storeId = 'store_1',
  String? menuItemId,
  bool isCoffeeSubscription = false,
  Map<String, String> extras = const <String, String>{},
}) =>
    NativeDeferredDeepLink(
      storeId: storeId,
      menuItemId: menuItemId,
      isCoffeeSubscription: isCoffeeSubscription,
      extras: extras,
    );
