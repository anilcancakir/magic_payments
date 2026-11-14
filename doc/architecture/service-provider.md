# Service Provider

`PaymentsServiceProvider` binds `PaymentsManager` into Magic's container under `'payments'` and resolves the build's billing driver at boot.

- [Overview](#overview)
- [Two-Phase Bootstrap Pattern](#two-phase)
- [register(): IoC Binding](#register)
- [boot(): Resolving the Platform Driver](#boot)
- [Config Root](#config)
- [Registering the Provider](#registration)
- [Related Documentation](#related-documentation)

<a name="overview"></a>
## Overview

`PaymentsServiceProvider` extends Magic's `ServiceProvider`, the base class every plugin extends. It owns two things: the `'payments'` container binding and the boot-time resolution of the driver this build serves.

```dart
class PaymentsServiceProvider extends ServiceProvider {
  PaymentsServiceProvider(super.app);

  @override
  void register() { /* ... */ }

  @override
  Future<void> boot() async { /* ... */ }
}
```

<a name="two-phase"></a>
## Two-Phase Bootstrap Pattern

| Phase | Method | Timing | Purpose |
|:------|:-------|:-------|:--------|
| 1 | `register()` | Synchronous, early | Bind services into the container |
| 2 | `boot()` | Async, after every provider has registered | Do anything that depends on another binding |

`register()` runs for every provider before `boot()` runs for any of them, and `Magic.init` loads the config factories before either, so `Config` is populated by the time this provider boots.

<a name="register"></a>
## register(): IoC Binding

`register()` does exactly one thing: bind the `PaymentsManager` singleton under the `'payments'` key. It reads no config and resolves no driver; both belong to `boot()`, because a driver resolved while other providers are still registering would be resolved against a half-built container.

```dart
app.singleton('payments', () => PaymentsManager());
```

After registration, any code in the app can resolve the manager by key:

```dart
final PaymentsManager manager = app.make<PaymentsManager>('payments');
```

<a name="boot"></a>
## boot(): Resolving the Platform Driver

`boot()` runs three steps, in this order:

1. It resolves the manager through the container, which proves that `register()` bound what a consumer will resolve.
2. It reads `payments.driver`. Absent or empty means the platform driver. Any value other than `'platform'` is logged at error level and ignored, because a config typo must not take an entitlement read offline.
3. It reads `PaymentsManager.billing`, which makes the package's conditional-import factory resolve the driver for this build, and logs at debug level which implementation answered and whether the web rail and the store rail are present.

`boot()` does not decide where a subscription is managed and never asks `kIsWeb` or `Platform.is`; the factory answers what the build is capable of, and the entitlement's `manageVia` answers where a subscription is managed. See [Drivers](../basics/drivers.md) for what each arm of the factory returns.

<a name="config"></a>
## Config Root

The provider reads only under `payments.*`, never under `magic_starter.*` or any other plugin's root. A plugin that read another plugin's key would stop working the moment it was installed without that plugin. The keys are listed in [Configuration](../getting-started/configuration.md).

<a name="registration"></a>
## Registering the Provider

`payments:install` adds the provider to `lib/config/app.dart` for you. By hand:

```dart
import 'package:magic_payments/magic_payments.dart';

final providers = [
  // ... other framework providers
  (app) => PaymentsServiceProvider(app),
];
```

The order inside the list does not matter to this provider's own boot. The five reads and the web rail call the `Http` facade when you use them, so the app's network provider has to be registered somewhere in the same list.

<a name="related-documentation"></a>
## Related Documentation

- [Payments Manager](./payments-manager.md): the singleton this provider binds.
- [Configuration](../getting-started/configuration.md): the `payments.*` keys.
- [Drivers](../basics/drivers.md): the conditional-import factory behind `boot()`.
- [Service Providers](https://anilcancakir.com/magic/docs/getting-started/service-providers): how Magic registers and boots providers.
