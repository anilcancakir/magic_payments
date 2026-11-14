# Installation

`magic_payments` is a multi-rail billing plugin for the Magic Framework, and this page adds it to an app, registers its provider and config, and shows which rail each platform gets.

- [Overview](#overview)
- [pub.dev Dependency Setup](#pubdev)
- [Service Provider Registration](#service-provider)
- [main.dart](#main-dart)
- [Which Platform Gets Which Rail](#platforms)
- [CLI Setup](#cli)
- [Next Steps](#next-steps)
- [Related Documentation](#related-documentation)

<a name="overview"></a>
## Overview

The plugin puts one entitlement contract in front of two kinds of payment rail: a hosted web checkout, and the platform's own in-app purchase system on iOS and Android. A consuming app asks two questions, what is this customer entitled to and where do they manage it, and the answers are rail-neutral.

> [!NOTE]
> Which rail a build has depends on its platform. Web has the web rail (`WebBillingService`) and no store rail. iOS and Android have the RevenueCat store rail (`StoreBillingService`) and no web rail. The five reads (`BillingService`) exist on every build. See [Rails](../basics/rails.md).

<a name="pubdev"></a>
## pub.dev Dependency Setup

Add the package, then register it with `dowel`, which publishes the config and wires the provider and the config factory in one step:

```bash
flutter pub add magic_payments
dart run magic:dowel plugin:install magic_payments
```

`plugin:install` applies the bundled `install.yaml`. The two sections below show what it leaves behind, so you can check its work or do it by hand.

<a name="service-provider"></a>
## Service Provider Registration

Register `PaymentsServiceProvider` in your app's provider list, the same way as any other Magic plugin:

```dart
import 'package:magic_payments/magic_payments.dart';

final providers = [
  // ... other providers
  (app) => PaymentsServiceProvider(app),
];
```

`PaymentsServiceProvider` runs the usual two-phase boot: `register()` binds one string-keyed singleton under `'payments'`, and `boot()` resolves the platform driver through the package's conditional-import factory. Neither phase requires a config file to exist for the five reads or the web rail to work. See [Service Provider](../architecture/service-provider.md) for the full sequence.

<a name="main-dart"></a>
## main.dart

Register the published config the same way every other plugin config is registered:

```dart
void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  await Magic.init(
    configFactories: [
      () => appConfig,
      () => paymentsConfig,
    ],
  );

  runApp(MyApp());
}
```

The five reads and the web rail boot without a single key, so a web-only app whose factory is missing still works and `payments:doctor` is the only thing that notices. The store rail is different: it reads `payments.revenuecat.public_sdk_key` the first time it needs the SDK, so on iOS and Android an unregistered factory turns into a `BillingException` under the customer's finger on the purchase sheet.

See [Configuration](./configuration.md) for every key and for why the store rail's key is resolved per platform.

<a name="platforms"></a>
## Which Platform Gets Which Rail

| Contract | Web | iOS and Android | Reason |
|:---------|:----|:----------------|:-------|
| `BillingService` (the five reads) | Yes | Yes | The backend is the authority on an entitlement whatever rail sold it, so a read never has to refuse a platform. |
| `WebBillingService` (`checkout`, `swap`, `cancel`, `openPortal`) | Yes | No (`null`) | The web rail hands the customer to a hosted checkout and portal that your backend creates. |
| `StoreBillingService` (`identify`, `purchase`, `products`, `restore`, `openStoreManagement`) | No (`null`) | Yes (`RevenueCatStoreService`) | StoreKit and Play Billing take the money, through RevenueCat. |

Which rail is present is decided by the package's own conditional-import factory, not by `kIsWeb` or `Platform.is`. macOS, Windows and Linux get the reads and no rail. See [Rails](../basics/rails.md) and [Drivers](../basics/drivers.md).

<a name="cli"></a>
## CLI Setup

`magic_payments` adds `payments:install`, `payments:configure` and `payments:doctor` to `dowel`. Once the plugin is registered, check a project with:

```bash
dart run magic:dowel payments:doctor
```

See [CLI Reference](../basics/cli.md) for what each command is for and which flags it takes.

<a name="next-steps"></a>
## Next Steps

1. Read [Configuration](./configuration.md) for the `payments.*` namespace.
2. Read [Rails](../basics/rails.md), especially the section on entitlement authority, before wiring a purchase button.
3. Read [Drivers](../basics/drivers.md) to see how a build resolves the driver it can serve and which backend endpoints the reads and writes call.

<a name="related-documentation"></a>
## Related Documentation

- [Configuration](./configuration.md): the `payments.*` keys.
- [Rails](../basics/rails.md): the three contracts.
- [CLI Reference](../basics/cli.md): the `payments:*` commands.
- [Service Provider](../architecture/service-provider.md): what the provider binds and boots.
- [Installation](https://anilcancakir.com/magic/docs/getting-started/installation): installing Magic itself.
