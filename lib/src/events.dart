/// The user-lifecycle events reported to Colada.
library;

import 'package:meta/meta.dart';

import 'exceptions.dart';

/// A user-lifecycle event reported to Colada, which forwards it to the correct
/// ad platform.
///
/// You never choose the ad platform — the backend resolves it from the user's
/// attribution record. Your job is to fire the right event at the right moment.
///
/// The nine supported events are modelled as subclasses so required fields are
/// enforced by the compiler rather than discovered at runtime. [Purchase] and
/// [Subscribe] cannot be constructed without an amount and currency, because an
/// event that reaches the ad platform with a value of zero silently degrades
/// campaign optimisation — a failure that costs money and produces no error.
///
/// ```dart
/// await Colada.track(
///   const Purchase(amount: 49.99, currency: 'SAR', orderId: 'ORD-1'),
/// );
/// ```
///
/// There is deliberately **no** `Download` event: the backend fires it
/// automatically from the attribution handshake, and the cleanest way to
/// enforce "never send this" is to make it impossible to express.
@immutable
sealed class ColadaEvent {
  /// Creates an event.
  const ColadaEvent();

  /// Wire name sent to the backend, e.g. `Purchase`.
  String get eventName;

  /// Event-specific fields, as sent in the backend's `metadata` object.
  Map<String, Object?> get metadata;

  /// Throws [ColadaInvalidEventException] if this event cannot be sent.
  ///
  /// Called for you by `Colada.track`. Runs entirely in Dart, before anything
  /// crosses to the native SDK, so a malformed event fails identically on
  /// Android and iOS instead of being rejected by one and quietly accepted by
  /// the other.
  @mustCallSuper
  void validate() {
    _validateMetadata(eventName, metadata);
  }

  /// Flat representation, for forwarding into your own analytics or logs.
  Map<String, Object?> toMap() => <String, Object?>{
        'eventName': eventName,
        'metadata': metadata,
      };

  @override
  String toString() => '$eventName($metadata)';

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is ColadaEvent &&
          other.runtimeType == runtimeType &&
          other.eventName == eventName &&
          _mapEquals(other.metadata, metadata);

  @override
  int get hashCode => Object.hash(
        runtimeType,
        eventName,
        Object.hashAllUnordered(
          metadata.entries
              .map((MapEntry<String, Object?> e) => (e.key, e.value)),
        ),
      );
}

/// Fire immediately after a user successfully creates an account.
///
/// **Ordering matters.** Call this only *after* your own sign-up call has
/// returned. Colada looks the user up by the id passed to `Colada.setUser`; if
/// that user does not exist yet the backend returns 404 and the event is lost.
///
/// **The one event that carries contact data.** The backend retains this
/// event's entire metadata object; every other event has only its declared
/// fields read and the rest discarded. That is why [name], [email] and
/// [phoneNumber] are offered here and nowhere else — sending them on another
/// event would reach the backend and be silently dropped.
///
/// All three are optional and sent raw. The backend hashes [phoneNumber] before
/// forwarding to ad platforms.
final class CompleteRegistration extends ColadaEvent {
  /// Creates a registration event carrying whatever the sign-up form collected.
  ///
  /// Pass only fields your form actually captured; do not fabricate values to
  /// "complete" the record.
  const CompleteRegistration({
    this.name,
    this.email,
    this.phoneNumber,
    this.extras = const <String, Object?>{},
  });

  /// The user's full name, as your sign-up form captured it.
  final String? name;

  /// The user's email address.
  final String? email;

  /// The user's phone number, raw. The backend hashes it before forwarding.
  final String? phoneNumber;

  /// Additional fields to retain against this event.
  final Map<String, Object?> extras;

  @override
  String get eventName => 'CompleteRegistration';

  @override
  Map<String, Object?> get metadata => <String, Object?>{
        // Extras first, so a declared field always wins over an extras entry of
        // the same name. Mirrors the native Android SDK's own ordering.
        ...extras,
        if (phoneNumber != null) 'phoneNumber': phoneNumber,
        if (name != null) 'name': name,
        if (email != null) 'email': email,
      };
}

/// Fire when a user actually authenticates.
///
/// **Not on every app open.** Restoring a saved session is not a login — call
/// `Colada.setUser` for that and do not fire this event, or a daily-active user
/// generates dozens of conversion events per day.
final class Login extends ColadaEvent {
  /// Creates a login event.
  const Login({this.extras = const <String, Object?>{}});

  /// Additional fields to attach.
  final Map<String, Object?> extras;

  @override
  String get eventName => 'Login';

  @override
  Map<String, Object?> get metadata => extras;
}

/// Fire after a payment has successfully completed — not when it is initiated.
final class Purchase extends ColadaEvent {
  /// Creates a purchase event.
  ///
  /// All three fields are required: an event that reaches the ad platform with
  /// a value of zero degrades campaign optimisation silently.
  const Purchase({
    required this.amount,
    required this.currency,
    required this.orderId,
  });

  /// Transaction value, e.g. `49.99`.
  final double amount;

  /// ISO 4217 currency code, e.g. `SAR`.
  final String currency;

  /// Your system's order or transaction identifier.
  final String orderId;

  @override
  String get eventName => 'Purchase';

  @override
  Map<String, Object?> get metadata => <String, Object?>{
        'amount': amount,
        'currency': currency,
        'orderId': orderId,
      };

  @override
  void validate() {
    super.validate();
    _requireFinite(eventName, 'amount', amount);
    _requireNotBlank(eventName, 'currency', currency);
    _requireNotBlank(eventName, 'orderId', orderId);
  }
}

/// Fire when a subscription is activated.
final class Subscribe extends ColadaEvent {
  /// Creates a subscription event.
  const Subscribe({required this.amount, required this.currency});

  /// Subscription value.
  final double amount;

  /// ISO 4217 currency code, e.g. `SAR`.
  final String currency;

  @override
  String get eventName => 'Subscribe';

  @override
  Map<String, Object?> get metadata => <String, Object?>{
        'amount': amount,
        'currency': currency,
      };

  @override
  void validate() {
    super.validate();
    _requireFinite(eventName, 'amount', amount);
    _requireNotBlank(eventName, 'currency', currency);
  }
}

/// Fire when a user adds an item to their cart.
final class AddToCart extends ColadaEvent {
  /// Creates an add-to-cart event.
  const AddToCart({this.extras = const <String, Object?>{}});

  /// Additional fields to attach.
  final Map<String, Object?> extras;

  @override
  String get eventName => 'AddToCart';

  @override
  Map<String, Object?> get metadata => extras;
}

/// Fire when a user starts the checkout flow, before payment.
final class InitiateCheckout extends ColadaEvent {
  /// Creates a checkout-started event.
  const InitiateCheckout({this.extras = const <String, Object?>{}});

  /// Additional fields to attach.
  final Map<String, Object?> extras;

  @override
  String get eventName => 'InitiateCheckout';

  @override
  Map<String, Object?> get metadata => extras;
}

/// Fire when a user views a product, store page, or menu item.
final class ViewContent extends ColadaEvent {
  /// Creates a content-viewed event.
  const ViewContent({this.extras = const <String, Object?>{}});

  /// Additional fields to attach.
  final Map<String, Object?> extras;

  @override
  String get eventName => 'ViewContent';

  @override
  Map<String, Object?> get metadata => extras;
}

/// Fire when a user submits an order, before payment is confirmed.
final class PlaceAnOrder extends ColadaEvent {
  /// Creates an order-placed event.
  const PlaceAnOrder({this.extras = const <String, Object?>{}});

  /// Additional fields to attach.
  final Map<String, Object?> extras;

  @override
  String get eventName => 'PlaceAnOrder';

  @override
  Map<String, Object?> get metadata => extras;
}

/// Fire when a user performs a search within the app.
final class Search extends ColadaEvent {
  /// Creates a search event.
  const Search({this.extras = const <String, Object?>{}});

  /// Additional fields to attach.
  final Map<String, Object?> extras;

  @override
  String get eventName => 'Search';

  @override
  Map<String, Object?> get metadata => extras;
}

/// Escape hatch for an event the backend supports but this SDK version does not
/// yet model, so a new backend event does not require an SDK release to use.
///
/// ⚠️ **Android only.** The native iOS SDK accepts a fixed vocabulary of nine
/// event names and cannot transmit any other, so tracking a [RawEvent] on iOS
/// throws [ColadaUnsupportedException]. Prefer the typed events, which work
/// everywhere.
///
/// The backend rejects unknown names with a 400, and this SDK cannot check the
/// name for you.
final class RawEvent extends ColadaEvent {
  /// Creates a raw event with the exact wire [eventName] the backend expects.
  const RawEvent({
    required this.eventName,
    this.extras = const <String, Object?>{},
  });

  @override
  final String eventName;

  /// Event-specific fields, matching the backend's `metadata` object.
  final Map<String, Object?> extras;

  @override
  Map<String, Object?> get metadata => extras;

  @override
  void validate() {
    super.validate();
    _requireNotBlank(
        eventName.isEmpty ? 'RawEvent' : eventName, 'eventName', eventName);
    if (eventName == 'Download') {
      throw const ColadaInvalidEventException(
        'Download',
        'is fired automatically by the attribution handshake and must never be '
            'tracked by the app.',
      );
    }
  }
}

/// Throws unless [value] is a usable number.
///
/// `NaN` and `Infinity` are rejected because they cannot be represented in JSON
/// and would either crash the platform-channel codec or reach the backend as
/// something meaningless.
void _requireFinite(String eventName, String field, double value) {
  if (!value.isFinite) {
    throw ColadaInvalidEventException(
      eventName,
      "requires a finite '$field', but got $value.",
    );
  }
}

/// Throws unless [value] contains something other than whitespace.
void _requireNotBlank(String eventName, String field, String value) {
  if (value.trim().isEmpty) {
    throw ColadaInvalidEventException(
      eventName,
      "requires a non-blank '$field'.",
    );
  }
}

/// Throws unless every metadata value can cross the platform channel.
///
/// The channel codec carries only `null`, `bool`, `num`, `String`, `List` and
/// `Map`. Anything else — a `DateTime`, an enum, a model object — fails deep
/// inside the codec with an opaque message, so it is rejected here instead,
/// naming the offending key.
void _validateMetadata(String eventName, Map<String, Object?> metadata) {
  for (final entry in metadata.entries) {
    _validateValue(eventName, entry.key, entry.value);
  }
}

void _validateValue(String eventName, String path, Object? value) {
  switch (value) {
    case null:
    case final bool _:
    case final String _:
      return;
    case final double d:
      if (!d.isFinite) {
        throw ColadaInvalidEventException(
          eventName,
          "metadata['$path'] is $d, which cannot be sent. Use a finite number.",
        );
      }
      return;
    case final num _:
      return;
    case final List<Object?> list:
      for (var i = 0; i < list.length; i++) {
        _validateValue(eventName, '$path[$i]', list[i]);
      }
      return;
    case final Map<Object?, Object?> map:
      for (final entry in map.entries) {
        if (entry.key is! String) {
          throw ColadaInvalidEventException(
            eventName,
            "metadata['$path'] has a non-String key (${entry.key.runtimeType}). "
            'Only String keys can be sent.',
          );
        }
        _validateValue(eventName, '$path.${entry.key}', entry.value);
      }
      return;
    default:
      throw ColadaInvalidEventException(
        eventName,
        "metadata['$path'] is a ${value.runtimeType}, which cannot cross the "
        'platform channel. Use null, bool, num, String, List or Map.',
      );
  }
}

/// Shallow map equality. Values are compared with `==`.
bool _mapEquals<K, V>(Map<K, V> a, Map<K, V> b) {
  if (identical(a, b)) return true;
  if (a.length != b.length) return false;
  for (final entry in a.entries) {
    if (!b.containsKey(entry.key) || b[entry.key] != entry.value) return false;
  }
  return true;
}
