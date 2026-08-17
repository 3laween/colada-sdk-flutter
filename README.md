# colada_sdk

Flutter SDK for [Colada](https://coladaapp.io) — mobile attribution and event
tracking. One async, type-safe Dart API over the native Colada Android and iOS
SDKs: initialize once, identify your users, track the events that matter, and
read back the campaign that drove each install.

## Features

- **One API, both platforms.** Android and iOS behave the same from Dart; where
  they genuinely differ, the difference is documented, not hidden — see
  [Platform differences](doc/PLATFORM_DIFFERENCES.md).
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
Never hardcode your key — pass it at build time.

```dart
import 'package:colada_sdk/colada_sdk.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Colada.initialize(
    const ColadaConfig(
      publicTenantKey: String.fromEnvironment('COLADA_TENANT_KEY'),
      strictMode: kDebugMode, // loud about platform gaps in debug
    ),
  );
  runApp(const MyApp());
}
```

Run it with the key supplied at build time:

```
flutter run --dart-define=COLADA_TENANT_KEY=pk_live_xxxx...
```

**2. Identify the user** after sign-up, after login, and on app start when
restoring a saved session:

```dart
await Colada.setUser(user.id);
```

> On iOS, call `setUser` **before** your first `track`. See
> [Platform differences](doc/PLATFORM_DIFFERENCES.md).

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
  // navigate to link.storeId / link.menuItemId
}
```

Deep links need no setup beyond declaring your scheme — see
[Deep links](doc/deep-links.md).

## Documentation

- [Getting started](doc/getting-started.md)
- [Events](doc/events.md)
- [Attribution](doc/attribution.md)
- [Deep links](doc/deep-links.md)
- [Configuration](doc/configuration.md)
- [Platform differences](doc/PLATFORM_DIFFERENCES.md)
- [Troubleshooting](doc/troubleshooting.md)

A complete, runnable app lives in [`example/`](example/).

## License

The source of this Flutter bridge is released under the [MIT License](LICENSE).
The native Colada Android and iOS binaries it depends on are proprietary and are
distributed separately (Maven Central and CocoaPods). MIT covers this bridge's
own source code only.
