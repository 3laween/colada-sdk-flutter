# Changelog

## 0.1.1

First release. A single Flutter package bridging the native Colada Android and
iOS SDKs behind one async, type-safe Dart API.

- **Lifecycle:** `Colada.initialize`, `isInitialized`, `deviceId`, with
  client-side tenant-key validation.
- **Identity:** `setUser` / `clearUser`.
- **Events:** nine typed lifecycle events plus `RawEvent` (Android), as sealed
  classes with compile-time required fields; `track` and `flush`.
- **Attribution:** `attributionStream` (broadcast, replays the latest value),
  `attribution`, and `consumeDeferredDeepLink`.
- **Deep links:** automatic forwarding on both platforms — cold start, warm
  start, custom scheme, and Universal / App Links — with an opt-out
  (`automaticDeepLinkForwarding: false`) and a manual `handleDeepLink`.
- **Diagnostics:** `Colada.logs`, and a typed `ColadaException` hierarchy so no
  raw platform exception ever reaches the app.
- **Configuration:** `strictMode`, `debug`, and `existingDeviceId`.
- Documented platform differences in `doc/PLATFORM_DIFFERENCES.md`.
