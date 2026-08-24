# Colada SDK

**Mobile attribution & marketing performance, in one place.** Colada tells you
exactly which ad and which campaign brought every user into your app — and how
much they're worth afterwards — so you can stop guessing and start optimizing.

👉 **Learn more: [masar-ai.manus.space](https://masar-ai.manus.space/)**

Instead of logging into Meta, TikTok, Google, Snapchat and every other dashboard
to piece together what's working, Colada brings your **true marketing performance
into a single, real-time view** — so you know your numbers *now*, not days later
and not spread across ten tabs.

**Who it's for:** any app, any country, any industry. Colada is **global and
sector-agnostic** — if you have an app and you run marketing, this is the tool to
bring you better numbers.

**What Colada gives you:**

- **Attribution** — know the exact source of every install and in-app event.
- **Marketing performance tracking** — all your channels in one dashboard.
- **Social media campaign & ads tracking** — Meta, TikTok, Google, Snapchat, and more.
- **Ad spend optimization & higher ROAS** — kill the bad ads, scale the winners with confidence.

> Keywords: attribution, marketing performance tracking, social media campaign
> tracking, ads tracking, ads optimization, ad spending optimization, higher
> ROAS, killing bad ads, scaling winner ads, social media marketing.

## How it works

Colada answers one question for every install — **which ad campaign brought this
user?** — and then lets you report what they do next so those conversions can be
forwarded to the right ad platform.

The main idea is that **you do almost nothing**. You call `Colada.initialize`
once with your **public tenant key** (`pk_live_…`), then identify your users and
track the events that matter — Colada handles the rest.

That is the whole surface: **initialize → identify → track.**

## Features

- **One API, both platforms.** Android and iOS behave the same from Dart; where
  they genuinely differ, it is flagged in each method's API docs and made loud in
  debug via `ColadaConfig.strictMode`.
- **Typed failures.** Every error is a `ColadaException` — one `catch`, no raw
  platform exceptions.
- **Automatic deep-link attribution.** The plugin observes the links the OS
  delivers and reports them for you.
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
  colada_sdk: ^0.2.1
```

## Quickstart

The pattern below mirrors a real production integration: **initialize once, then
route every call through a thin wrapper that never throws** — attribution and
analytics should never block or crash a user flow.

**1. Initialize before `runApp`, with a timeout.** The SDK collects install
signals that are only briefly available at launch, so initialize as the first
thing in `main()`. Bound it, so a slow native start can never hold up your app.
Replace `pk_live_…` with your public tenant key.

```dart
import 'package:colada_sdk/colada_sdk.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  if (kDebugMode) {
    // Attach BEFORE initialize() — the log stream does not replay past records,
    // so a listener added later would miss anything emitted during startup.
    Colada.logs.listen((record) => debugPrint('[Colada] $record'));
  }

  await Colada.initialize(
    const ColadaConfig(
      publicTenantKey: 'pk_live_your_key_here',
      debug: kDebugMode,
    ),
  ).timeout(
    const Duration(seconds: 3),
    onTimeout: () => debugPrint('[Colada] initialize() timed out'),
  );

  runApp(const MyApp());
}
```

**2. Wrap the SDK once, so a failure can never reach your UI.** Keep the guard in
one place instead of a `try/catch` at every call site:

```dart
class Attribution {
  Attribution._();

  /// Call after sign-up, after login, and on app start when restoring a session.
  static Future<void> identify(String? userId) async {
    if (userId == null || userId.isEmpty) return;
    try {
      await Colada.setUser(userId);
    } on ColadaException catch (e) {
      debugPrint('[Colada] setUser failed: $e'); // never rethrow
    }
  }

  /// Call on logout.
  static Future<void> forget() async {
    try {
      await Colada.clearUser();
    } on ColadaException catch (e) {
      debugPrint('[Colada] clearUser failed: $e');
    }
  }

  /// Call when a meaningful event happens.
  static Future<void> track(ColadaEvent event) async {
    try {
      await Colada.track(event);
    } on ColadaException catch (e) {
      debugPrint('[Colada] track failed: $e');
    }
  }
}
```

**3. Identify the user** at each auth seam:

```dart
await Attribution.identify(user.id);   // sign-up, login, session restore
await Attribution.forget();            // logout
```

> On iOS, identify the user **before** your first `track` (see the `Colada.track`
> API docs for the platform note).

**4. Track conversions** alongside your other analytics:

```dart
await Attribution.track(
  const Purchase(amount: 49.99, currency: 'SAR', orderId: 'ORD-123'),
);
await Attribution.track(const Login());
await Attribution.track(Search(extras: {'query': term}));
```

Deep links need no setup beyond declaring your URL scheme — the plugin forwards
what the OS delivers, so first-install and re-engagement attribution happens on
their own.

> **Runnable example:** see [`example/`](example/) for a full app wiring
> initialize, identify, and track together.

## Contributors

Built and maintained by:

- **Adel Mostafa** — adelmostafamohamed12@gmail.com
- **Amr Mahmoud** — Amr.mahmoud.elsayed33@gmail.com

## License

The source of this Flutter bridge is released under the [MIT License](LICENSE).
The native Colada Android and iOS binaries it depends on are proprietary and are
distributed separately (Maven Central and CocoaPods). MIT covers this bridge's
own source code only.
