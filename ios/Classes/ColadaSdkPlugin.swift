import Flutter
import UIKit

/// Colada Flutter plugin — iOS entry point.
///
/// Phase 1 skeleton: registers with the Flutter engine but exposes no
/// functionality yet. The Pigeon-generated host API is wired in Phase 4, and
/// the bridge to the native Colada iOS SDK follows in Phases 9 to 12.
public class ColadaSdkPlugin: NSObject, FlutterPlugin {
  public static func register(with registrar: FlutterPluginRegistrar) {
    // No channels registered yet; Pigeon setup arrives in Phase 4.
  }
}
