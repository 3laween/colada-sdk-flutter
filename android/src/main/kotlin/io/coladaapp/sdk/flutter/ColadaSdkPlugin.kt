package io.coladaapp.sdk.flutter

import io.flutter.embedding.engine.plugins.FlutterPlugin

/**
 * Colada Flutter plugin — Android entry point.
 *
 * Phase 4 registers the Pigeon-generated host API and answers every call with
 * [ColadaErrorCode.NOT_INITIALIZED]. The real bridge to the native Colada
 * Android SDK arrives in Phases 5 to 8, method by method.
 *
 * Answering with a proper Colada error rather than leaving the channel
 * unregistered is deliberate: an unregistered channel surfaces in Dart as a
 * `MissingPluginException`, which the Dart layer reports as "this platform is
 * not supported" — an actively misleading message on Android. A registered
 * handler that reports "not implemented yet" is the honest answer.
 */
class ColadaSdkPlugin : FlutterPlugin, ColadaHostApi {

    override fun onAttachedToEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        ColadaHostApi.setUp(binding.binaryMessenger, this)
        // The two event channels (attribution, logs) are registered in Phase 7,
        // together with the native listeners that feed them.
    }

    override fun onDetachedFromEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        ColadaHostApi.setUp(binding.binaryMessenger, null)
    }

    // --- ColadaHostApi ------------------------------------------------------
    //
    // Phase 5 replaces initialize/isInitialized/deviceId, Phase 6 the identity
    // and event calls, Phase 7 attribution, Phase 8 deep links.

    override fun initialize(config: NativeConfig, callback: (Result<Unit>) -> Unit) {
        callback(notImplemented("initialize"))
    }

    override fun isInitialized(callback: (Result<Boolean>) -> Unit) {
        callback(notImplemented("isInitialized"))
    }

    override fun deviceId(callback: (Result<String?>) -> Unit) {
        callback(notImplemented("deviceId"))
    }

    override fun setUser(externalUserId: String, callback: (Result<Unit>) -> Unit) {
        callback(notImplemented("setUser"))
    }

    override fun clearUser(callback: (Result<Unit>) -> Unit) {
        callback(notImplemented("clearUser"))
    }

    override fun track(
        eventName: String,
        metadata: Map<String, Any?>,
        callback: (Result<Unit>) -> Unit,
    ) {
        callback(notImplemented("track"))
    }

    override fun flush(callback: (Result<Unit>) -> Unit) {
        callback(notImplemented("flush"))
    }

    override fun currentAttribution(callback: (Result<NativeAttribution?>) -> Unit) {
        callback(notImplemented("currentAttribution"))
    }

    override fun consumeDeferredDeepLink(
        callback: (Result<NativeDeferredDeepLink?>) -> Unit,
    ) {
        callback(notImplemented("consumeDeferredDeepLink"))
    }

    override fun handleDeepLink(url: String, callback: (Result<Unit>) -> Unit) {
        callback(notImplemented("handleDeepLink"))
    }

    // Must be a Pigeon FlutterError, not a custom Throwable: the generated
    // `wrapError` only forwards code/message/details for FlutterError, and
    // falls back to the exception's CLASS NAME as the code for anything else.
    // A custom exception here would reach Dart as code
    // "ColadaBridgeException", which maps to no typed exception at all.
    private fun <T> notImplemented(method: String): Result<T> = Result.failure(
        FlutterError(
            ColadaErrorCode.NOT_INITIALIZED,
            "Colada.$method is not wired on Android yet (arrives in Phases 5-8).",
        ),
    )
}

/**
 * Error codes reported to Dart.
 *
 * ⚠️ These strings are a three-language contract. They must stay identical to
 * `ColadaErrorCode` in `lib/src/error_codes.dart` and to the Swift constants
 * in `ios/colada_sdk/Sources/colada_sdk/ColadaSdkPlugin.swift`. A mismatch does
 * not break the call — the failure still reaches the app — but it loses its
 * type, which is the entire point of the exception hierarchy.
 */
object ColadaErrorCode {
    const val NOT_INITIALIZED = "colada/not-initialized"
    const val INVALID_CONFIG = "colada/invalid-config"
    const val INVALID_EVENT = "colada/invalid-event"
    const val MISSING_USER = "colada/missing-user"
    const val BACKEND_REJECTED = "colada/backend-rejected"
    const val DELIVERY_FAILED = "colada/delivery-failed"
    const val NETWORK = "colada/network"
    const val TOKEN_EXPIRED = "colada/token-expired"
    const val DEVICE_IDENTITY_UNAVAILABLE = "colada/device-identity-unavailable"
    const val TRACKING_BLOCKED = "colada/tracking-blocked"
    const val UNSUPPORTED = "colada/unsupported"
}

/**
 * Builds the Pigeon error that carries a Colada code across to Dart.
 *
 * `details` becomes the Dart `PlatformException.details` map that
 * `exception_mapper.dart` reads for structured fields such as `statusCode`
 * and `attempts`.
 */
internal fun coladaError(
    code: String,
    message: String,
    details: Map<String, Any?>? = null,
): FlutterError = FlutterError(code, message, details)
