# Configuration

The `payments.*` config root holds the one driver mode and the store rail's RevenueCat credentials, and nothing that decides which rail a build serves.

- [Overview](#overview)
- [The Keys](#keys)
- [The Store Rail's Key, Per Platform](#store)
- [Product Keys Are Not Configured Here Either](#product-keys)
- [Why the Rail Itself Is Not Configured](#why)
- [Runtime Config Access](#runtime)
- [Related Documentation](#related-documentation)

<a name="overview"></a>
## Overview

Every Magic plugin owns a config root, merged into the framework's `ConfigRepository` when `Magic.init` runs and read back through `Config.get(key)`. This package's root is `payments.*`, and `PaymentsServiceProvider.boot()` plus the store driver are the only code that reads under it: never `magic_starter.*`, and never a key another plugin owns.

<a name="keys"></a>
## The Keys

`payments:install` publishes them to `lib/config/payments.dart` and registers the config factory in `Magic.init`. The published file is Dart, and the key is blank until you fill it in:

```dart
import 'package:flutter/foundation.dart' show TargetPlatform, defaultTargetPlatform;

Map<String, dynamic> get paymentsConfig => {
  'payments': {
    'driver': 'platform',
    'revenuecat': {
      'public_sdk_key': switch (defaultTargetPlatform) {
        TargetPlatform.iOS => '', // your appl_ key
        TargetPlatform.android => '', // your goog_ key
        _ => '',
      },
      'subject_label': 'team',
    },
  },
};
```

| Key | Type | Default | Read by |
|:----|:-----|:--------|:--------|
| `payments.driver` | `String` | `'platform'` | `PaymentsServiceProvider.boot()` |
| `payments.revenuecat.public_sdk_key` | `String` | none, required on iOS and Android | `RevenueCatStoreService`, on first use |
| `payments.revenuecat.subject_label` | `String` | none; the published file sets `'team'` | `RevenueCatStoreService`, as a subscriber attribute |

`payments.driver` is `'platform'`, the only value the package serves, and it means "resolve the driver from the build", which is what the conditional-import factory does. The key exists so that choice is recorded rather than implicit. Any other value is refused by the CLI (`payments:configure --driver=x` exits 1) and reported by `payments:doctor`. If one reaches the runtime anyway, the provider logs an error and wires the platform driver regardless, because a config typo must not take an entitlement read offline.

`payments.revenuecat.*` is read only by the store rail, so a web-only or desktop-only app needs none of it. `payments:doctor` reports what it finds under `public_sdk_key` without failing on it, for exactly that reason: it runs on your laptop and cannot know which build you will ship.

`subject_label` is optional and names what the paying subject is. When it is set and non-empty, `identify()` records `<label>:<id>` as a subscriber attribute, so a support ticket reads "team:42" rather than a bare id. A failure to record it is logged and does not fail the identify.

> [!WARNING]
> `public_sdk_key` is the public key. It ships inside the app bundle by design. Your project's secret key authenticates your server to the RevenueCat API and must never appear in this file or anywhere else in a client build.

> [!NOTE]
> A driver of your own is registered in code, not named here: `Payments.extend(PaymentsManager.webRole, () => MyRail())`. A config string cannot resolve to a factory, and it cannot change which files a build compiled in. See [Drivers](../basics/drivers.md).

<a name="store"></a>
## The Store Rail's Key, Per Platform

RevenueCat issues a separate public SDK key for each store: `appl_...` for the App Store app and `goog_...` for the Play app. One shared string cannot serve both, which is why the stub resolves the value instead of stating it: `lib/config/payments.dart` is Dart, not JSON, so an expression is as valid there as a literal.

The stub uses `defaultTargetPlatform` rather than `Platform.isIOS`, because `dart:io` is unavailable on web and this config is compiled into every build, web included. The `_` arm covers every platform that has no store, and an empty string there is correct: nothing outside iOS and Android reads the key.

A blank or absent value is refused at purchase time rather than silently. The driver logs and throws a `BillingException` with `BillingErrorCode.notConfigured`, naming the missing key, so the failure points at the config instead of surfacing as an SDK error far from its cause. `Payments.store` is still non-null on those platforms, because whether a device has a store and whether you have configured it are two different questions; the first is what the null check answers.

<a name="product-keys"></a>
## Product Keys Are Not Configured Here Either

No config key names a product. A purchase takes the vendor's catalogue key (`'pro_annual'`), and the rail resolves it from its own catalogue: on the store rail the key must equal a RevenueCat package identifier in one of your offerings, on the web rail it is a key your backend maps to a price. Adding or repricing a product is a change in the dashboard or the backend, never in `lib/config/payments.dart`. A key with no package is refused with `BillingErrorCode.productUnavailable`; see [Rails](../basics/rails.md#product-keys).

`dart run magic:dowel payments:doctor --json` reports the one thing here an agent can check, whether `public_sdk_key` is `present`, `absent` or `blank`, and never its value.

<a name="why"></a>
## Why the Rail Itself Is Not Configured

Which rail a build can serve is a structural question rather than a preference: a web build has `dart.library.html`, a mobile or desktop build has `dart.library.io`, and neither a config flag nor a runtime check changes which files were compiled in. So the platform driver is resolved by the package's own conditional-import factory, which `boot()` reads, not by a config lookup.

A key claiming to enable or disable a rail would be a second answer to a question the import graph already settles, and two answers eventually disagree. Credentials are the opposite case: no import can supply them, which is why they do live here. See [Drivers](../basics/drivers.md) for how the factory decides, including why the io arm asks one runtime question of its own.

<a name="runtime"></a>
## Runtime Config Access

If you add a key under `payments.*` yourself (for a custom driver registered through `Payments.extend`, for instance), read it the way any Magic config value is read:

```dart
final String? value = Config.get<String>('payments.your_key');
```

`Config.get` returns `null` for an absent key or one of the wrong type; pass a default as the second argument or use `??`. The store driver reads its key exactly this way, then trims it and refuses an empty result.

<a name="related-documentation"></a>
## Related Documentation

- [Installation](./installation.md): adding the package and registering the config factory.
- [Service Provider](../architecture/service-provider.md): where `payments.driver` is read.
- [Rails](../basics/rails.md): the store rail that consumes the SDK key.
- [CLI Reference](../basics/cli.md): `payments:configure` and `payments:doctor`.
- [Configuration](https://anilcancakir.com/magic/docs/getting-started/configuration): how Magic loads config factories.
