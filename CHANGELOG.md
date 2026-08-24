# Changelog

## 0.2.1

- **More reliable deep link attribution on iOS.** Re-engagement links now
  attribute correctly on iOS, matching Android — so campaigns that bring existing
  users back into your app are measured accurately on both platforms.
- **Clearer documentation.** Every event and method now includes a short
  description and a usage example.

## 0.2.0

Synced with the native cores' latest public API, and pins both natives at 0.2.0.
**Breaking** changes are marked — migrate before upgrading.

- **BREAKING — `ColadaDeferredDeepLink` is extras-only.** The typed `storeId`,
  `menuItemId` and `isCoffeeSubscription` properties were removed; the
  destination is now a single `Map<String, String> extras`. Colada's own fields
  appear under the keys `storeId` / `menuItemId` / `isCoffeeSubscription` (the
  last as `'true'`/`'false'`), alongside any tenant-specific fields. Migrate
  `link.storeId` → `link.extras['storeId']`, etc. `hasDestination` is now "any
  extras key other than `isCoffeeSubscription`". Both platforms populate the map
  identically.
- **BREAKING — `Purchase` / `Subscribe` required fields.** `Purchase` requires
  `amount` + `currency` + `orderId`, `Subscribe` requires `amount` + `currency`,
  all non-nullable. The implicit `'SAR'` currency default is gone — pass the
  currency explicitly. (These were already enforced in Dart; called out here for
  the record and because the native cores now reject a missing field.)
- **`clearUser()`** now maps to the native SDKs' explicit `clearUser()` on both
  platforms (previously `setExternalUserId(nil)` on iOS), so the outgoing user's
  queued events are flushed before the identity is cleared on iOS too.
- **Tracking before `setUser` is no longer an error on iOS.** Both platforms now
  buffer-and-hold the event and release it on the next `setUser`/`clearUser`.
  `ColadaMissingUserException` is retained for compatibility but is no longer
  raised for this case.
- **`Colada.logs` is now rich on iOS too.** The plugin registers a native
  `logSink` on both platforms (the iOS core gained one), so SDK records flow to
  the stream on iOS as well as Android. Verbosity follows `ColadaConfig.debug`.
- **Native cores pinned to 0.2.0.** Picks up the latest native attribution
  improvements. No Dart API or behavior change on the Flutter side.

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
