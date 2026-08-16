/// Configuration for the Colada SDK.
library;

import 'package:meta/meta.dart';

import 'exceptions.dart';

/// Configuration passed once to `Colada.initialize`.
///
/// Only [publicTenantKey] is required. Everything else has a sensible default,
/// and most integrations will never set the others.
///
/// ```dart
/// await Colada.initialize(
///   ColadaConfig(
///     publicTenantKey: const String.fromEnvironment('COLADA_TENANT_KEY'),
///     strictMode: kDebugMode,
///   ),
/// );
/// ```
@immutable
class ColadaConfig {
  /// Creates a configuration.
  const ColadaConfig({
    required this.publicTenantKey,
    this.debug = false,
    this.strictMode = false,
    this.existingDeviceId,
    this.automaticDeepLinkForwarding = true,
  });

  /// Your app's public API key, issued by Colada.
  ///
  /// Format: [tenantKeyPrefix] followed by exactly [tenantKeyHexLength]
  /// hexadecimal characters.
  ///
  /// **Hardcode this per app build — never read it from a deep link, and never
  /// commit it.** Supply it at build time, e.g.
  /// `--dart-define=COLADA_TENANT_KEY=...`, and read it with
  /// `String.fromEnvironment`.
  ///
  /// This key ships inside your app bundle and can be extracted from it, so it
  /// is not a secret in the strict sense — but it is still a credential worth
  /// keeping out of source control. Never use a `sk_live_` secret key here;
  /// those must never reach a mobile app.
  final String publicTenantKey;

  /// Enables verbose logging on `Colada.logs`.
  ///
  /// Leave `false` in release builds. The SDK is quiet by default so it never
  /// pollutes your console.
  ///
  /// ⚠️ **Android only.** The native iOS SDK has no verbose-logging switch, so
  /// on iOS this affects only the log records this package's own bridge emits.
  final bool debug;

  /// Turns silent degradation into loud failure.
  ///
  /// The SDK is built to degrade rather than break your app: a capability that
  /// is unavailable on the current platform is skipped, with a warning on
  /// `Colada.logs`. During development that same forgiveness hides mistakes.
  /// With this on, those warnings become thrown
  /// [ColadaUnsupportedException]s instead.
  ///
  /// **Enable in debug builds; never in release:**
  ///
  /// ```dart
  /// ColadaConfig(publicTenantKey: key, strictMode: kDebugMode)
  /// ```
  final bool strictMode;

  /// **Migration only.** An existing stable device identifier to adopt.
  ///
  /// If your app already has a stable per-device identifier from a previous
  /// attribution implementation, pass it here so the SDK adopts it instead of
  /// generating a new one — otherwise every existing user gets a fresh identity
  /// detached from their attribution history.
  ///
  /// Read **only** on the first launch after adding the SDK, when it has no
  /// identifier of its own. Once an identifier is stored this value is ignored
  /// permanently, so leaving it in place across releases cannot reset anyone.
  ///
  /// ⚠️ **Android only.** The native iOS SDK has no way to adopt an existing
  /// identifier, so on iOS this is ignored and a warning is emitted. Plan for
  /// iOS identities to reset when you adopt this SDK.
  ///
  /// New integrations must leave this `null`. Passing a value that is not
  /// genuinely stable per-device will corrupt attribution.
  final String? existingDeviceId;

  /// Whether the SDK forwards incoming deep links to Colada by itself.
  ///
  /// `true` (the default) means the plugin observes the links the OS delivers
  /// and reports them for you — you do not need to touch `MainActivity` or your
  /// `AppDelegate`, and you do not need to call `Colada.handleDeepLink`.
  ///
  /// Set to `false` only if you want to own that step, in which case you
  /// **must** call `Colada.handleDeepLink` yourself for every incoming link.
  /// Exactly one of the two is correct: doing both is harmless (the native SDK
  /// de-duplicates), doing neither loses your highest-accuracy attribution
  /// signal.
  ///
  /// Using a package such as `app_links` to *observe* links for your own
  /// routing is fine and unrelated — leave this `true`.
  final bool automaticDeepLinkForwarding;

  /// Required prefix of a valid [publicTenantKey].
  static const String tenantKeyPrefix = 'pk_live_';

  /// Prefix of Colada's server-side secret keys, which must never reach an app.
  static const String _secretKeyPrefix = 'sk_live_';

  /// Number of hexadecimal characters that must follow [tenantKeyPrefix].
  static const int tenantKeyHexLength = 64;

  static const int _keyVisibleChars = 4;

  static final RegExp _hex = RegExp(r'^[0-9a-fA-F]+$');

  /// Throws [ColadaInvalidConfigException] if this configuration cannot be used.
  ///
  /// Called for you by `Colada.initialize`. The rules mirror the native Android
  /// SDK's own validator exactly, so a key accepted here is accepted there, and
  /// a key rejected here would have been rejected there.
  ///
  /// One problem per field, reported in field order: a key that is both the
  /// wrong prefix and the wrong length produces one actionable message rather
  /// than a pile that buries the real issue.
  void validate() {
    _validateTenantKey();
    if (existingDeviceId != null && existingDeviceId!.trim().isEmpty) {
      throw const ColadaInvalidConfigException(
        'existingDeviceId',
        'was blank. Omit it entirely unless you are migrating a real '
            'identifier from a previous attribution implementation.',
      );
    }
  }

  void _validateTenantKey() {
    const field = 'publicTenantKey';
    if (publicTenantKey.trim().isEmpty) {
      throw const ColadaInvalidConfigException(
        field,
        'is required but was blank.',
      );
    }
    // Checked before the prefix rule so the message names the real danger. A
    // secret key in a mobile app is extractable from the bundle by anyone: this
    // is a live credential leak, not a typo.
    if (publicTenantKey.startsWith(_secretKeyPrefix)) {
      throw const ColadaInvalidConfigException(
        field,
        "looks like a SECRET key ('$_secretKeyPrefix…'). Secret keys must never "
        'ship in a mobile app — anyone can extract it from your bundle. Use '
        "the public key ('$tenantKeyPrefix…') instead.",
      );
    }
    if (!publicTenantKey.startsWith(tenantKeyPrefix)) {
      throw const ColadaInvalidConfigException(
        field,
        "must start with '$tenantKeyPrefix'.",
      );
    }
    final body = publicTenantKey.substring(tenantKeyPrefix.length);
    if (body.length != tenantKeyHexLength) {
      throw ColadaInvalidConfigException(
        field,
        "must be '$tenantKeyPrefix' followed by exactly $tenantKeyHexLength hex "
        'characters, but had ${body.length}.',
      );
    }
    if (!_hex.hasMatch(body)) {
      throw const ColadaInvalidConfigException(
        field,
        'contains non-hexadecimal characters.',
      );
    }
  }

  /// Masks a tenant key for logging, e.g. `pk_live_a1b2…`.
  ///
  /// Never log a key in full — logs get pasted into bug reports and chat.
  static String redactKey(String key) {
    if (key.length <= _keyVisibleChars) return '***';
    const wanted = tenantKeyPrefix.length + _keyVisibleChars;
    return '${key.substring(0, wanted < key.length ? wanted : key.length)}…';
  }

  /// Returns a copy with the given fields replaced.
  ColadaConfig copyWith({
    String? publicTenantKey,
    bool? debug,
    bool? strictMode,
    String? existingDeviceId,
    bool? automaticDeepLinkForwarding,
  }) =>
      ColadaConfig(
        publicTenantKey: publicTenantKey ?? this.publicTenantKey,
        debug: debug ?? this.debug,
        strictMode: strictMode ?? this.strictMode,
        existingDeviceId: existingDeviceId ?? this.existingDeviceId,
        automaticDeepLinkForwarding:
            automaticDeepLinkForwarding ?? this.automaticDeepLinkForwarding,
      );

  /// Never prints the tenant key in full — see [redactKey].
  @override
  String toString() => 'ColadaConfig(publicTenantKey: '
      '${redactKey(publicTenantKey)}, debug: $debug, strictMode: $strictMode, '
      'existingDeviceId: ${existingDeviceId ?? 'null'}, '
      'automaticDeepLinkForwarding: $automaticDeepLinkForwarding)';

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is ColadaConfig &&
          other.publicTenantKey == publicTenantKey &&
          other.debug == debug &&
          other.strictMode == strictMode &&
          other.existingDeviceId == existingDeviceId &&
          other.automaticDeepLinkForwarding == automaticDeepLinkForwarding;

  @override
  int get hashCode => Object.hash(
        publicTenantKey,
        debug,
        strictMode,
        existingDeviceId,
        automaticDeepLinkForwarding,
      );
}
