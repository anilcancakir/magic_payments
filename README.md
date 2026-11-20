<p align="center">
  <img src="https://raw.githubusercontent.com/anilcancakir/magic_payments/master/screenshots/logo.png" width="120" alt="Magic Payments logo" />
</p>

<h1 align="center">Magic Payments</h1>

<p align="center">
  <strong>Ask one question, what is this customer entitled to, whichever rail sold the subscription.</strong><br/>
  Subscription billing for Magic apps: the <code>Payments</code> facade reads the entitlement your backend serves and hands you the web rail (hosted checkout and portal) and the store rail (App Store and Play, through RevenueCat) as nullable contracts, so no widget branches on the platform.
</p>

<p align="center">
  <a href="https://pub.dev/packages/magic_payments"><img src="https://img.shields.io/pub/v/magic_payments.svg" alt="pub package"></a>
  <a href="https://github.com/anilcancakir/magic_payments/actions/workflows/ci.yml"><img src="https://img.shields.io/github/actions/workflow/status/anilcancakir/magic_payments/ci.yml?branch=master&label=CI" alt="CI"></a>
  <a href="https://codecov.io/gh/anilcancakir/magic_payments"><img src="https://codecov.io/gh/anilcancakir/magic_payments/graph/badge.svg" alt="codecov"></a>
  <a href="https://opensource.org/licenses/MIT"><img src="https://img.shields.io/badge/License-MIT-blue.svg" alt="License: MIT"></a>
  <a href="https://pub.dev/packages/magic_payments/score"><img src="https://img.shields.io/pub/points/magic_payments" alt="pub points"></a>
</p>

<p align="center">
  <a href="https://anilcancakir.com/magic/docs/payments">Documentation</a> ·
  <a href="https://pub.dev/packages/magic_payments">pub.dev</a> ·
  <a href="https://github.com/anilcancakir/magic_payments/issues">Issues</a>
</p>

## At a glance

| Fact | Value |
|---|---|
| Package | [`magic_payments`](https://pub.dev/packages/magic_payments) |
| Install | `flutter pub add magic_payments`, then `dart run magic:dowel plugin:install magic_payments` |
| Import | `package:magic_payments/magic_payments.dart` |
| Entry points | `Payments` (facade), `PaymentsManager`, `PaymentsServiceProvider`, `BillingService`, `WebBillingService`, `StoreBillingService`, `StoreIdentitySync`, `BillingException`; `payments:install`, `payments:configure`, `payments:doctor` (CLI) |
| Platforms | The reads run on web, iOS, Android, macOS, Windows and Linux. The web rail exists on web builds, the store rail on iOS and Android. |
| Requires | Dart >=3.13, Flutter >=3.47, `magic` ^1.0.0, and a backend that serves the `/billing` endpoints |
| Dependencies | `magic`, `purchases_flutter` (store rail); dowel runs the commands |
| License | MIT |

## Install

```bash
flutter pub add magic_payments
dart run magic:dowel plugin:install magic_payments
```

`plugin:install` applies the bundled `install.yaml`: it publishes `lib/config/payments.dart`, registers `PaymentsServiceProvider` in `lib/config/app.dart` and adds `paymentsConfig` to the `configFactories` of `lib/main.dart`. `dart run magic:dowel payments:install` applies the same plan again, and `--dry-run` shows it without writing.

On iOS and Android fill in `payments.revenuecat.public_sdk_key` (RevenueCat's public SDK key, `appl_...` for the App Store and `goog_...` for Play) in `lib/config/payments.dart`. Web and desktop builds never read it. Check the wiring:

```bash
dart run magic:dowel payments:doctor
```

## Entitlement

Read what the customer is entitled to and send them to the surface that owns the subscription.

```dart
import 'package:magic_payments/magic_payments.dart';

// `openUrl` stands for your app's own URL launcher.
Future<void> manageSubscription(
  Future<void> Function(String url) openUrl,
) async {
  try {
    final BillingEntitlement entitlement = await Payments.currentEntitlement();

    if (!entitlement.subscribed) return;

    switch (entitlement.manageVia) {
      case ManageVia.portal:
        final WebBillingService? web = Payments.web;

        if (web != null) {
          // Web builds only.
          await web.openPortal();
        } else {
          // iOS, Android and desktop have no portal call, and iOS and Android
          // must not link to the web portal: say where it is managed, no link.
        }
      case ManageVia.appStore:
      case ManageVia.playStore:
        final StoreBillingService? store = Payments.store;
        final String? manageUrl = entitlement.manageUrl;

        if (store != null) {
          // iOS and Android builds.
          await store.openStoreManagement();
        } else if (manageUrl != null) {
          // The web app and desktop: `Payments.store` is null there.
          await openUrl(manageUrl);
        } else {
          // Nothing to open: say it is managed in the App Store or Google Play,
          // without a link.
        }
      case ManageVia.none:
        break;
    }
  } on BillingException catch (error) {
    // Decide what to tell the customer from `error.code`, never `error.message`.
  }
}
```

The five reads are the same calls on `Payments.billing` and as static methods on `Payments`:

| Member | Returns | Request |
|--------|---------|---------|
| `currentEntitlement()` | `BillingEntitlement` | `GET /billing` |
| `getPlans()` | `List<Map<String, dynamic>>`, one backend row per tier, undecoded | `GET /billing/plans` |
| `getUsage()` | `List<UsageStat>` | `GET /billing/usage` |
| `getInvoices({cursor})` | `BillingInvoicesPage` (`invoices`, `nextCursor`) | `GET /billing/invoices` |
| `getPaymentMethod()` | `PaymentMethod` | `GET /billing/payment-method` |

The requests go through magic's `Http` facade to the base URL your app configures. Failure modes:

| Situation | What happens |
|-----------|--------------|
| A non-success response, or a body of the wrong shape | The read throws `BillingException`. |
| The backend serves no `/billing/usage` route | `getUsage()` throws `BillingException`. `magic-starter-laravel` registers that route only when the app binds its usage contract. |
| The payment rail is down on the backend | `getPaymentMethod()` answers a `PaymentMethod` with every field null. Gate the copy on `PaymentMethod.available`, not on a null `last4`. |
| A platform that is neither web nor `dart:io` | Every read throws `UnsupportedPlatformException`, never an empty answer. |

`BillingEntitlement.manageVia` is where the subscription is managed (`portal`, `appStore`, `playStore`, `none`), and it follows the rail that sold it, not the platform the app runs on. A subscription bought on a phone is still managed in its store when the customer opens the web app, where `Payments.store` is `null`: `openStoreManagement()` exists on iOS and Android builds only, so a store case without the rail uses `BillingEntitlement.manageUrl` when the backend sent one, and otherwise only tells the customer which store manages it. `manageUrl` is `null` for `portal` by design, because `openPortal()` mints a short-lived page on web builds. The backend decides the entitlement; a `true` from a purchase or a returned checkout is a hint, so read `currentEntitlement()` again after any write.

## Web rail

`Payments.web` is a `WebBillingService` on web builds and `null` everywhere else. Your backend owns the payment vendor and creates the hosted pages; the package calls your backend and opens what it returns.

```dart
import 'package:magic_payments/magic_payments.dart';

Future<void> upgrade() async {
  final WebBillingService? web = Payments.web;
  if (web == null) return;

  await web.checkout(
    productKey: 'pro_annual',
    successUrl: 'https://example.com/billing?checkout=success',
    cancelUrl: 'https://example.com/billing?checkout=cancel',
  );
}
```

| Member | Returns | Request |
|--------|---------|---------|
| `checkout({productKey, successUrl, cancelUrl})` | `BillingCheckoutSession`; opens `checkoutUrl` in an in-app web view | `POST /billing/checkout` |
| `swap({productKey})` | `void` | `POST /billing/swap` |
| `cancel()` | `void`; usually end of period, so the entitlement keeps granting until `currentPeriodEnd` | `POST /billing/cancel` |
| `openPortal({returnUrl})` | The portal URL; opens it in an in-app web view | `GET /billing/portal` |

`productKey` is your catalogue key (`'pro_annual'`): one key names the tier and the cycle, and it is the `key` of an entry in a `getPlans()` row's `products` list. Failure modes:

| Situation | What happens |
|-----------|--------------|
| `Payments.web` off a web build | `null`. Check it before rendering the button. |
| 422 with `code: product_not_sellable` | `BillingException` with `BillingErrorCode.productUnavailable`. |
| 402 with `billing.reason` `payment_failed` or `payment_requires_action` | `BillingException` with `paymentDeclined` or `paymentRequiresAction`; nothing changed. |
| The launcher refuses the hosted page | `BillingException`, never a silent success. |
| Any other refusal | `BillingException` with `BillingErrorCode.unknown`. |

## Store rail

`Payments.store` is a `StoreBillingService` on iOS and Android and `null` on web, on macOS, Windows and Linux, and on a platform the package has never seen. `RevenueCatStoreService` serves it through `purchases_flutter`.

```dart
import 'package:magic_payments/magic_payments.dart';

Future<void> buy() async {
  final StoreBillingService? store = Payments.store;
  if (store == null) return;

  // The rail cannot see a subscription billed on the web.
  final BillingEntitlement entitlement = await Payments.currentEntitlement();
  if (entitlement.manageVia == ManageVia.portal) return;

  final bool bought = await store.purchase('pro_annual');

  // The store is done; the backend's webhook may not have caught up. Treat a
  // stale answer as "not yet", never as a failure.
  if (bought) await Payments.currentEntitlement();
}
```

| Member | Meaning |
|--------|---------|
| `identify(appUserId)` | Binds the rail to the paying account. `StoreIdentitySync` calls it for you. |
| `purchase(productKey, {context})` | `true` when the store completed a transaction, `false` when the customer dismissed the sheet. `context` is a `PurchaseContext` that lets a Play change be ranked as an upgrade or a downgrade. |
| `products(productKeys)` | `Map<String, StoreProductOffer>` with the store's own localised prices. A key the store has no product for is absent from the map. |
| `restore()` | `true` when the store handed back a purchase, `false` when it had nothing for the identified account. |
| `openStoreManagement()` | Opens the store's subscription screen. Throws `BillingException` when the account holds no store subscription. |
| `store` | `ManageVia.appStore` or `ManageVia.playStore`. |
| `lastChangeTiming` | After a `true` from `purchase`, `immediate`, `atRenewal` or `null` (nothing to announce). |

Switch on `BillingException.code`, a `BillingErrorCode`, never on `message`:

| Code | Cause |
|------|-------|
| `notConfigured` | `payments.revenuecat.public_sdk_key` is blank or absent. Non-null `Payments.store` does not mean configured. |
| `notIdentified` | `StoreIdentitySync.billableId` is unset or answers `null` or an empty string when a `purchase` or `restore` asks. |
| `identityMismatch` | The SDK is bound to another account than the one asking. |
| `managedElsewhere` | The other store sells a subscription the customer holds. |
| `unmappedActiveProduct` | An active Play product cannot be ranked, so no replacement mode is safe. |
| `productUnavailable` | No store product for the key, or the backend will not sell it. |
| `pending`, `receiptInUse`, `alreadyOwned`, `network`, `store` | The store's own outcome; `unknown` is a failure no driver named. |

The store rail does not refuse a subscription your backend bills on the web, because RevenueCat cannot see it. Gate a store purchase on `entitlement.manageVia != ManageVia.portal` yourself.

## Keeping the store identified

`purchase` and `restore` refuse unless the rail is bound to the account that pays. `StoreIdentitySync` keeps it bound; you supply who pays.

```dart
import 'package:magic_payments/magic_payments.dart';

Future<void> wireStore(String? Function() payingId) async {
  StoreIdentitySync.billableId = payingId;
  StoreIdentitySync.attach();
  await StoreIdentitySync.syncNow();
}
```

`attach()` only adds a listener: it identifies on every `Auth.stateNotifier` change after the call. `Magic.init` has already restored a returning user's session, so call `wireStore` after `await Magic.init(...)` and let `syncNow()` identify that user straight away. `purchase` and `restore` run the same sync before they check, so a missed call costs an identify at the first purchase, not a refusal. After a switch of the paying subject that does not change auth state, such as a team switch, call `await StoreIdentitySync.syncNow()` again. `notIdentified` means the `billableId` callback is unset or answers `null` or an empty string: nothing can be identified then, and every store purchase throws it.

## Command line

| Command | Does | Writes files |
|---------|------|--------------|
| `payments:install` | Publishes the config, registers the provider, wires the config factory. Idempotent; `--dry-run`, `--force`. | Yes |
| `payments:configure` | `--show` prints `driver`; `--driver=platform` sets it. Any other value exits 1. | Yes |
| `payments:doctor` | Checks the dependency, the config, the provider, the config factory and the store key. `--verbose`, `--json`. | No |

`payments:doctor` reports the store rail's key as a state and never its value (`present` in `--json` and `declared` in the human report, otherwise `absent` or `blank`), and a blank key warns without failing. It cannot say which rails a build serves, because that is a compile-time import. Only `payments_doctor` is an MCP tool; the two commands that write files are not.

## For AI coding agents

Rules for an agent writing code against this package. Each one is a mistake that charges a customer wrongly or hides a purchase button that should show.

| Do | Because |
|----|---------|
| Import only `package:magic_payments/magic_payments.dart` | Everything under `src/` is private, and `package:magic_payments/cli.dart` is for the command line only. |
| Check `Payments.web` and `Payments.store` for `null` before rendering a purchase affordance | A `null` rail is a build that cannot serve it; rendering a button and catching the refusal is the shape this package replaced. |
| Branch management screens on `BillingEntitlement.manageVia` | A subscription is managed where its rail sold it, whatever platform the app runs on. Never use `kIsWeb` or `Platform.is*`. |
| Read `currentEntitlement()` again after `purchase`, `checkout`, `swap` or `cancel` | The backend's answer is the grant; the write's own result is only a hint. |
| Switch on `BillingException.code` | `message` is prose that differs per rail and locale. |
| Set `StoreIdentitySync.billableId` and call `attach()` before any store purchase, then `await StoreIdentitySync.syncNow()` after `Magic.init` | `purchase` and `restore` identify on demand, but throw `notIdentified` when `billableId` is unset or answers `null` or an empty string. |
| Never put a RevenueCat secret key in `lib/config/payments.dart` | `public_sdk_key` is the public key and ships in the app bundle. |
| Never render a link to web checkout or the web portal on iOS or Android | App Review Guideline 3.1.3(a) restricts steering a customer to another purchase method. |
| Show intro-offer copy only when `StoreProductOffer.introEligible` is `true` | An `introPrice` alone says the product has an offer, not that this customer may take it. |
| Register a driver of your own with `Payments.extend(role, factory)`, never through `payments.driver` | `driver` accepts `platform` only, and the roles are `billing`, `web` and `store`. |
| In a test, call `Payments.forgetDrivers()` in `tearDown` | `PaymentsManager` is a `static final` that outlives a container reset. |

## Dependencies

`magic` for the container, the `Http`, `Config`, `Log`, `Launch` and `Auth` facades and the service provider base class; `purchases_flutter` for the RevenueCat SDK behind the store rail; dowel to run the `payments:*` commands through `dart run magic:dowel`. The command tree lives in `package:magic_payments/cli.dart`, which imports no UI toolkit, so the commands run as a plain Dart process and the runtime barrel carries no command code.

## Links

- [Documentation](https://anilcancakir.com/magic/docs/payments/getting-started/installation): installation, configuration, the three rails, drivers, the manager and the provider
- [API reference](https://pub.dev/documentation/magic_payments/latest/)
- [llms.txt](llms.txt) and the [agent skill](skills/magic-payments/SKILL.md) for AI coding agents: `npx skills add anilcancakir/magic_payments`
- [Changelog](CHANGELOG.md)
- [Report an issue](https://github.com/anilcancakir/magic_payments/issues)
- [Security policy](SECURITY.md)

## License

MIT, see [LICENSE](LICENSE). Built by [Anılcan Çakır](https://anilcancakir.com).
