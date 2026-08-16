/// Colada Flutter SDK — mobile attribution and event tracking.
///
/// This package is a bridge over the native Colada Android and iOS SDKs. It is
/// the single public entry point; everything under `src/` is private and must
/// never be imported directly.
///
/// Start with [Colada], the facade you call for everything.
///
/// ```dart
/// await Colada.initialize(
///   const ColadaConfig(
///     publicTenantKey: String.fromEnvironment('COLADA_TENANT_KEY'),
///   ),
/// );
/// await Colada.setUser(user.id);
/// await Colada.track(const Purchase(
///   amount: 49.99,
///   currency: 'SAR',
///   orderId: 'ORD-123',
/// ));
/// ```
library;

export 'src/attribution.dart'
    show ColadaAttribution, ColadaDeferredDeepLink, ColadaMatchMethod;
export 'src/colada.dart' show Colada;
export 'src/config.dart' show ColadaConfig;
export 'src/events.dart'
    show
        AddToCart,
        ColadaEvent,
        CompleteRegistration,
        InitiateCheckout,
        Login,
        PlaceAnOrder,
        Purchase,
        RawEvent,
        Search,
        Subscribe,
        ViewContent;
export 'src/exceptions.dart'
    show
        ColadaBackendRejectedException,
        ColadaDeliveryFailedException,
        ColadaDeviceIdentityUnavailableException,
        ColadaException,
        ColadaInvalidConfigException,
        ColadaInvalidEventException,
        ColadaMissingUserException,
        ColadaNetworkException,
        ColadaNotInitializedException,
        ColadaTokenExpiredException,
        ColadaTrackingBlockedException,
        ColadaUnsupportedException;
export 'src/logging.dart' show ColadaLogLevel, ColadaLogRecord;
