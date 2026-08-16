package io.coladaapp.sdk.flutter

import io.flutter.embedding.engine.plugins.FlutterPlugin

/**
 * Colada Flutter plugin — Android entry point.
 *
 * Phase 1 skeleton: registers with the Flutter engine but exposes no
 * functionality yet. The Pigeon-generated host API is wired in Phase 4, and the
 * bridge to the native Colada Android SDK follows in Phases 5 to 8.
 */
class ColadaSdkPlugin : FlutterPlugin {
    override fun onAttachedToEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        // No channels registered yet; Pigeon setup arrives in Phase 4.
    }

    override fun onDetachedFromEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        // Nothing to tear down yet.
    }
}
