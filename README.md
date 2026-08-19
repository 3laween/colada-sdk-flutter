# Colada SDK

Flutter SDK for [Colada](https://coladaapp.io) — mobile attribution and event
tracking. One async, type-safe Dart API over the native Colada Android and iOS
SDKs: initialize once, identify your users, track the events that matter, and
read back the campaign that drove each install.

## How it works

Colada answers one question for every install — **which ad campaign brought this
user?** — and then lets you report what they do next so those conversions can be
forwarded to the right ad platform.

The main idea is that **you do almost nothing**. You call `Colada.initialize`
once with your **public tenant key** (`pk_live_…`), and from there the native SDK
owns the entire backend conversation:

- **Auth is automatic.** It exchanges your tenant key for a short-lived session
  token and attaches it to every backend request itself. You never see, store, or
  refresh a token — there is no API for it, by design.
- **Attribution is automatic.** On first install — and on any ad-driven deep-link
  open — the SDK runs an *attribution handshake* on its own and resolves the
  campaign (via the deep link, install referrer, clipboard, or a probabilistic
  match). An ordinary app open does nothing.
- **You just identify and track.** Call `setUser` after login/sign-up, and
  `track` when meaningful events happen. The backend links each event to that
  user's attribution and forwards it to the ad platform that drove the install.

You read the resolved campaign back on a stream, and consume any deferred
deep-link destination to route a first-time user to the right screen. That is the
whole surface: **initialize → identify → track → read attribution.**

## Features

- **One API, both platforms.** Android and iOS behave the same from Dart; where
  they genuinely differ, it is flagged in each method's API docs and made loud in
  debug via `ColadaConfig.strictMode`.
- **Type-safe events.** Nine lifecycle events as sealed classes; required fields
  are enforced by the compiler, not discovered at runtime.
- **Typed failures.** Every error is a `ColadaException` — one `catch`, no raw
  platform exceptions.
- **Automatic deep-link attribution.** The plugin observes the links the OS
  delivers and reports them for you; no `MainActivity` or `AppDelegate` code.
- **Attribution as a stream.** Subscribe late and still receive the result — the
  stream replays the most recent value.

## Requirements

| Platform | Minimum |
|----------|---------|
| Android  | minSdk 23, compileSdk 36, JDK 17 |
| iOS      | iOS 13.0, Swift 5.9 |
| Flutter  | 3.22+ / Dart 3.4+ |

## Install

```yaml
dependencies:
  colada_sdk: ^0.1.1
```

## Quickstart

**1. Initialize before `runApp`.** The SDK collects install signals that are
only briefly available at launch, so initialize as the first thing in `main()`.
Replace `YOU_PUBLIC_KEY` with your public tenant key (`pk_live_…`).

```dart
import 'package:colada_sdk/colada_sdk.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Colada.initialize(
    const ColadaConfig(
      publicTenantKey: 'YOU_PUBLIC_KEY',
      strictMode: kDebugMode, // loud about platform gaps in debug
    ),
  );
  runApp(const MyApp());
}
```

**2. Identify the user** after sign-up, after login, and on app start when
restoring a saved session:

```dart
await Colada.setUser(user.id);
```

> On iOS, call `setUser` **before** your first `track` (see the `Colada.track`
> API docs for the platform note).

**3. Track events** when they happen:

```dart
await Colada.track(
  const Purchase(amount: 49.99, currency: 'SAR', orderId: 'ORD-123'),
);
```

**4. Read attribution** to learn which campaign drove the install:

```dart
Colada.attributionStream.listen((a) {
  if (a.matched) debugPrint('campaign: ${a.utmCampaign}');
});

final link = await Colada.consumeDeferredDeepLink();
if (link != null && link.hasDestination) {
  // navigate using link.extras (e.g. link.extras['storeId'])
}
```

Deep links need no setup beyond declaring your URL scheme — the plugin forwards
what the OS delivers, so first-install and re-engagement handshakes happen on
their own.

## Contributors

Built and maintained by:

- **Adel Mostafa** — adelmostafamohamed12@gmail.com
- **Amr Mahmoud** — Amr.mahmoud.elsayed33@gmail.com

## License

The source of this Flutter bridge is released under the [MIT License](LICENSE).
The native Colada Android and iOS binaries it depends on are proprietary and are
distributed separately (Maven Central and CocoaPods). MIT covers this bridge's
own source code only.
