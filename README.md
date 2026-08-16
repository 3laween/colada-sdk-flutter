# colada_sdk

Flutter SDK for [Colada](https://coladaapp.io) — mobile attribution and event
tracking. A single Flutter package that bridges the native Colada Android and
iOS SDKs, exposing one async, type-safe Dart API across both platforms.

> **Status: in development.** This package is being built phase by phase. The
> public API, the native bridge, and the example app are not yet present. This
> README will grow into the integration guide as those phases land.

## Platforms

| Platform | Minimum |
|----------|---------|
| Android  | minSdk 23, compileSdk 36, JDK 17 |
| iOS      | iOS 13.0, Swift 5.9 |

## Installation

Not yet published to pub.dev. Once released:

```yaml
dependencies:
  colada_sdk: ^1.0.0
```

## License

The source of this Flutter bridge is released under the [MIT License](LICENSE).

Note that the **native Colada Android and iOS binaries this package depends on
are proprietary** and are distributed separately (Maven Central and CocoaPods,
respectively). MIT covers this bridge's own source code only.
