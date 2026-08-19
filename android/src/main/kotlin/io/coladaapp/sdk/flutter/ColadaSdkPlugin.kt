package io.coladaapp.sdk.flutter

import android.content.Context
import android.content.Intent
import android.os.Handler
import android.os.Looper
import io.coladaapp.sdk.AttributionListener
import io.coladaapp.sdk.AttributionResult
import io.coladaapp.sdk.Colada
import io.coladaapp.sdk.ColadaConfig
import io.coladaapp.sdk.ColadaLogLevel
import io.coladaapp.sdk.ColadaLogSink
import io.coladaapp.sdk.DeferredDeepLink
import io.flutter.embedding.engine.plugins.FlutterPlugin
import io.flutter.embedding.engine.plugins.activity.ActivityAware
import io.flutter.embedding.engine.plugins.activity.ActivityPluginBinding
import io.flutter.plugin.common.PluginRegistry.NewIntentListener

/**
 * Colada Flutter plugin — Android entry point.
 *
 * Bridges the Pigeon-generated [ColadaHostApi] and the two event channels onto
 * the published native Colada Android SDK (io.coladaapp:colada-android:0.1.1),
 * with no changes to that SDK.
 *
 * Built across Phases 5–8:
 *  - **5** lifecycle: [initialize] / [isInitialized] / [deviceId].
 *  - **6** identity & events: [setUser] / [clearUser] / [track] / [flush].
 *  - **7** attribution, deferred deep link, logs (the two event channels).
 *  - **8** automatic deep-link forwarding (ActivityAware + NewIntentListener).
 *
 * ### Threading
 *
 * Every [ColadaHostApi] method is invoked by Pigeon on the platform (main)
 * thread, and every native call it makes returns in well under a millisecond
 * (the native SDK does its real work on background threads), so the callbacks
 * complete synchronously on the main thread. The native SDK delivers attribution
 * on the main thread and log records on an arbitrary thread; both are hopped to
 * the main thread before touching an [io.flutter.plugin.common.EventChannel]
 * sink, which Flutter requires.
 *
 * ### Context
 *
 * Holds only the application [Context], never the Activity — the native SDK
 * makes the same guarantee, and holding an Activity would leak it across a
 * rotation.
 */
class ColadaSdkPlugin :
    FlutterPlugin,
    ActivityAware,
    NewIntentListener,
    ColadaHostApi {

    private val mainHandler = Handler(Looper.getMainLooper())

    private var applicationContext: Context? = null
    private var activityBinding: ActivityPluginBinding? = null

    /** The bridge's own flag: true once native [Colada.initialize] has returned. */
    private var initialized = false

    /** Mirrors `ColadaConfig.automaticDeepLinkForwarding`; known only after init. */
    private var autoForward = true

    // Event-channel sinks, set when Dart subscribes and cleared when it cancels.
    private var attributionEventSink: PigeonEventSink<NativeAttribution>? = null
    private var logEventSink: PigeonEventSink<NativeLogRecord>? = null

    // A subscription to the attribution stream that arrived before init; the
    // native listener is attached once init completes (see [initialize]).
    private var pendingAttributionListen = false

    // Phase 8 — deep links that arrived before init are buffered here and
    // replayed once the native SDK is up (R2). Bounded so a pathological sender
    // cannot grow it without limit. Touched only on the main thread.
    private val pendingLinks = ArrayDeque<String>()
    private var coldStartHandled = false

    // --- FlutterPlugin ------------------------------------------------------

    override fun onAttachedToEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        applicationContext = binding.applicationContext
        val messenger = binding.binaryMessenger
        ColadaHostApi.setUp(messenger, this)
        AttributionResolvedStreamHandler.register(messenger, attributionStreamHandler)
        LogEmittedStreamHandler.register(messenger, logStreamHandler)
    }

    override fun onDetachedFromEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        ColadaHostApi.setUp(binding.binaryMessenger, null)
        // Drop the native attribution listener so a detached engine cannot leak
        // it — the native SDK holds listeners strongly. Safe if never attached.
        Colada.removeAttributionListener(attributionListener)
        attributionEventSink = null
        logEventSink = null
        applicationContext = null
    }

    // --- ColadaHostApi: lifecycle (Phase 5) ---------------------------------

    override fun initialize(config: NativeConfig, callback: (Result<Unit>) -> Unit) {
        val ctx = applicationContext
        if (ctx == null) {
            callback(
                Result.failure(
                    coladaError(
                        ColadaErrorCode.NOT_INITIALIZED,
                        "Plugin is not attached to an engine.",
                    ),
                ),
            )
            return
        }
        autoForward = config.automaticDeepLinkForwarding
        try {
            // baseUrl is intentionally NOT taken from Dart: a public package must
            // not let anyone point the SDK at an arbitrary host. Pass the SDK's
            // own default so the six-argument constructor can carry the logSink.
            val nativeConfig = ColadaConfig(
                config.publicTenantKey,
                ColadaConfig.DEFAULT_BASE_URL,
                config.debug,
                config.strictMode,
                config.existingDeviceId,
                nativeLogSink,
            )
            Colada.initialize(ctx, nativeConfig)
            initialized = true

            // A stream subscriber that arrived before init now gets its native
            // listener; the native SDK replays the last attribution to it.
            if (pendingAttributionListen) {
                Colada.addAttributionListener(attributionListener)
                pendingAttributionListen = false
            }
            // Phase 8: replay links buffered before the SDK was up.
            drainPendingLinks()

            callback(Result.success(Unit))
        } catch (e: Exception) {
            // Android's SDK is designed never to throw here except under
            // strictMode, where a config it dislikes surfaces as an exception.
            // Dart already validated the config, so reaching this means the two
            // validators disagree — surface it as a config error, loudly.
            callback(
                Result.failure(
                    coladaError(
                        ColadaErrorCode.INVALID_CONFIG,
                        e.message ?: "The native SDK rejected the configuration.",
                    ),
                ),
            )
        }
    }

    override fun isInitialized(callback: (Result<Boolean>) -> Unit) {
        callback(Result.success(Colada.isInitialized))
    }

    override fun deviceId(callback: (Result<String?>) -> Unit) {
        callback(Result.success(Colada.deviceId))
    }

    // --- ColadaHostApi: identity & events (Phase 6) -------------------------

    override fun setUser(externalUserId: String, callback: (Result<Unit>) -> Unit) {
        Colada.setUser(externalUserId)
        callback(Result.success(Unit))
    }

    override fun clearUser(callback: (Result<Unit>) -> Unit) {
        Colada.clearUser()
        callback(Result.success(Unit))
    }

    override fun track(
        eventName: String,
        metadata: Map<String, Any?>,
        callback: (Result<Unit>) -> Unit,
    ) {
        try {
            // The wire-name overload: the native SDK builds the event via
            // ColadaEvent.of(name, map) and runs its own required-field
            // validation, so the bridge does not duplicate it. Dart validated
            // first, so an IllegalArgumentException here means the two validators
            // disagree — a bug worth surfacing rather than swallowing.
            Colada.track(eventName, metadata)
            callback(Result.success(Unit))
        } catch (e: IllegalArgumentException) {
            callback(
                Result.failure(
                    coladaError(
                        ColadaErrorCode.INVALID_EVENT,
                        e.message ?: "The native SDK rejected the event.",
                    ),
                ),
            )
        }
    }

    override fun flush(callback: (Result<Unit>) -> Unit) {
        Colada.flush()
        callback(Result.success(Unit))
    }

    // --- ColadaHostApi: attribution & deep links (Phase 7) ------------------

    override fun currentAttribution(callback: (Result<NativeAttribution?>) -> Unit) {
        callback(Result.success(Colada.attribution?.toNative()))
    }

    override fun consumeDeferredDeepLink(
        callback: (Result<NativeDeferredDeepLink?>) -> Unit,
    ) {
        callback(Result.success(Colada.consumeDeferredDeepLink()?.toNative()))
    }

    override fun handleDeepLink(url: String, callback: (Result<Unit>) -> Unit) {
        // The manual escape hatch: only reached from Dart when the host opted
        // out of automatic forwarding. The native SDK de-duplicates, so a link
        // it has already seen via the automatic path is harmless.
        Colada.handleDeepLink(url)
        callback(Result.success(Unit))
    }

    // --- Event channels (Phase 7) -------------------------------------------

    private val attributionStreamHandler = object : AttributionResolvedStreamHandler() {
        override fun onListen(p0: Any?, sink: PigeonEventSink<NativeAttribution>) {
            attributionEventSink = sink
            // Attach the native listener only now, so the value the native SDK
            // replays on registration lands in a live sink. If Dart subscribed
            // before init, defer the attach until init completes.
            if (initialized) {
                Colada.addAttributionListener(attributionListener)
            } else {
                pendingAttributionListen = true
            }
        }

        override fun onCancel(p0: Any?) {
            attributionEventSink = null
            pendingAttributionListen = false
            Colada.removeAttributionListener(attributionListener)
        }
    }

    private val logStreamHandler = object : LogEmittedStreamHandler() {
        override fun onListen(p0: Any?, sink: PigeonEventSink<NativeLogRecord>) {
            logEventSink = sink
        }

        override fun onCancel(p0: Any?) {
            logEventSink = null
        }
    }

    private val attributionListener = object : AttributionListener {
        override fun onAttributionResolved(result: AttributionResult) {
            val native = result.toNative()
            mainHandler.post { attributionEventSink?.success(native) }
        }
    }

    private val nativeLogSink = object : ColadaLogSink {
        override fun onLog(level: ColadaLogLevel, message: String, error: Throwable?) {
            // Level crosses as its lowercase wire string; ColadaLogLevel.fromWire
            // on the Dart side degrades an unknown value to `info` rather than
            // throwing. The Throwable crosses as its toString(), never its stack
            // trace: traces are noisy and can carry internal class names into an
            // integrator's console.
            val record = NativeLogRecord(
                level = level.name.lowercase(),
                message = message,
                error = error?.toString(),
            )
            mainHandler.post { logEventSink?.success(record) }
        }
    }

    // --- ActivityAware + automatic deep-link forwarding (Phase 8) -----------

    override fun onAttachedToActivity(binding: ActivityPluginBinding) {
        activityBinding = binding
        binding.addOnNewIntentListener(this)
        // The cold-start intent has already been delivered by the time Flutter
        // boots; read it once. It is forwarded (or buffered, if init has not run
        // yet) exactly once for the life of the process.
        handleColdStartIntent(binding.activity.intent)
    }

    override fun onReattachedToActivityForConfigChanges(binding: ActivityPluginBinding) {
        activityBinding = binding
        binding.addOnNewIntentListener(this)
        // Deliberately do NOT re-read the launch intent: it was handled on first
        // attach, and re-forwarding it on every rotation would double-count.
    }

    override fun onDetachedFromActivityForConfigChanges() {
        activityBinding?.removeOnNewIntentListener(this)
        activityBinding = null
    }

    override fun onDetachedFromActivity() {
        activityBinding?.removeOnNewIntentListener(this)
        activityBinding = null
    }

    override fun onNewIntent(intent: Intent): Boolean {
        forwardIntent(intent)
        // We are an observer of the link, not its owner: return false so other
        // plugins (e.g. app_links) still receive it.
        return false
    }

    private fun handleColdStartIntent(intent: Intent?) {
        if (coldStartHandled) return
        coldStartHandled = true
        if (intent != null) forwardIntent(intent)
    }

    private fun forwardIntent(intent: Intent) {
        // Only VIEW-style intents carry a link; a plain launcher intent has no
        // data and is ignored.
        val url = intent.dataString ?: return
        if (initialized) {
            // Manual mode (autoForward == false): the host owns forwarding, so
            // the plugin stays out of the way.
            if (autoForward) Colada.handleDeepLink(url)
        } else {
            if (pendingLinks.size >= MAX_PENDING_LINKS) pendingLinks.removeFirst()
            pendingLinks.addLast(url)
        }
    }

    private fun drainPendingLinks() {
        val links = pendingLinks.toList()
        pendingLinks.clear()
        // In manual mode the buffered links belong to the host; drop them.
        if (!autoForward) return
        for (url in links) Colada.handleDeepLink(url)
    }

    // --- native <-> channel mapping -----------------------------------------

    private fun AttributionResult.toNative(): NativeAttribution = NativeAttribution(
        matched = matched,
        // Forward the native SDK's own wire string; the Dart layer parses it
        // with an `unknown` fallback so a backend-added strategy never breaks an
        // older plugin.
        matchMethod = matchMethod.wireValue,
        utmSource = utmSource,
        utmCampaign = utmCampaign,
        utmMedium = utmMedium,
        utmContent = utmContent,
        utmTerm = utmTerm,
        clickId = clickId,
        attributionId = attributionId,
        tenantKey = tenantKey,
        deferredDeepLink = deferredDeepLink?.toNative(),
        extras = extras,
    )

    private fun DeferredDeepLink.toNative(): NativeDeferredDeepLink =
        // The destination is now a single string map; the native SDK exposes no
        // typed store/menu/coffee fields anymore. storeId/menuItemId/
        // isCoffeeSubscription live inside `extras` under those keys.
        NativeDeferredDeepLink(extras = extras)

    private companion object {
        const val MAX_PENDING_LINKS = 5
    }
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
