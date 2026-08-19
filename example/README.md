# Colada SDK — usage example

A minimal, end-to-end integration: initialize once, identify the user, track an
event, and read the campaign that brought them. Replace `YOU_PUBLIC_KEY` with
your own public tenant key (`pk_live_…`).

```dart
import 'package:colada_sdk/colada_sdk.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Colada.initialize — starts the SDK. Call once, before runApp().
  await Colada.initialize(
    const ColadaConfig(
      publicTenantKey: 'YOU_PUBLIC_KEY',
      strictMode: kDebugMode,
    ),
  );

  runApp(const MyApp());
}

class MyApp extends StatefulWidget {
  const MyApp({super.key});

  @override
  State<MyApp> createState() => _MyAppState();
}

class _MyAppState extends State<MyApp> {
  String _status = 'initialized';

  @override
  void initState() {
    super.initState();

    // Colada.attributionStream — the campaign that brought this user, or
    // organic if there is none. Listen once and update your UI when it arrives.
    Colada.attributionStream.listen((a) {
      setState(() {
        _status = a.matched
            ? 'campaign: ${a.utmCampaign} (${a.matchMethod.name})'
            : 'organic install';
      });
    });

    _onSignedIn('user-123');
  }

  Future<void> _onSignedIn(String userId) async {
    // Colada.setUser — tell the SDK which user is signed in. Call after
    // sign-up, after login, and when restoring a saved session.
    await Colada.setUser(userId);

    // Colada.consumeDeferredDeepLink — if the user arrived from a campaign that
    // points to a specific screen, this returns that destination once so you
    // can navigate to it.
    final link = await Colada.consumeDeferredDeepLink();
    if (link != null && link.hasDestination) {
      // The destination is a string map: read link.extras['storeId'] etc.
      debugPrint('open ${link.extras}');
    }
  }

  // Colada.track — report an event when it happens. Events are typed, so
  // required fields (amount, currency, …) are checked at compile time.
  Future<void> _buy() => Colada.track(
        const Purchase(amount: 49.99, currency: 'SAR', orderId: 'ORD-123'),
      );

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      home: Scaffold(
        appBar: AppBar(title: const Text('Colada SDK example')),
        body: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(_status),
              const SizedBox(height: 16),
              ElevatedButton(
                onPressed: _buy,
                child: const Text('Track Purchase'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
```

The whole surface: **initialize → identify → track → read attribution.**
