# Drivers

A driver implements the billing contracts against one platform's own transport, and the package's conditional-import factory decides which driver a build gets.

- [Quick Reference](#quick-reference)
- [Driver Concept](#concept)
- [The Conditional-Import Factory](#factory)
- [BillingServiceWeb](#web-driver)
- [BillingServiceIo](#io-driver)
- [BillingServiceStub](#stub-driver)
- [Overriding a Driver](#extend)
- [Gotchas](#gotchas)
- [Related Documentation](#related-documentation)

<a name="quick-reference"></a>
## Quick Reference

| Arm | `createBillingService()` | `createWebBillingService()` | `createStoreBillingService()` |
|:----|:-------------------------|:----------------------------|:------------------------------|
| Web (`dart.library.html`) | `BillingServiceWeb` | `BillingServiceWeb` | `null` |
| Io (`dart.library.io`) | `BillingServiceIo` | `null` | `RevenueCatStoreService` on iOS and Android, `null` elsewhere |
| Stub (default) | `BillingServiceStub` | `null` | `null` |

<a name="concept"></a>
## Driver Concept

`BillingServiceWeb` and `BillingServiceIo` both talk to your backend over Magic's `Http` facade, against the base URL your app configures for it; `BillingServiceStub` talks to nothing, because it is reached on a platform this package has never seen. The store rail, `RevenueCatStoreService`, talks to the RevenueCat SDK on the device. Which one a build gets is decided once, at compile time, by the package's own conditional import, not by a runtime check.

<a name="factory"></a>
## The Conditional-Import Factory

`billing_service_factory.dart` is the one file in the package that knows about platforms, and it knows through the import graph rather than through a branch:

```dart
import 'billing_service_stub.dart'
    if (dart.library.html) 'billing_service_web.dart'
    if (dart.library.io) 'billing_service_io.dart'
    as impl;

BillingService createBillingService() => impl.createBillingService();
WebBillingService? createWebBillingService() => impl.createWebBillingService();
StoreBillingService? createStoreBillingService() => impl.createStoreBillingService();
```

Three arms, and the third is not optional. Drop the `dart.library.io` guard and every iOS and Android build resolves the stub, whose every read throws, with no analyzer error on any platform to say so.

Every arm declares all three functions, because a conditional import resolves a whole file: each arm has to answer for every rail, even when its answer to two of them is `null`.

The io arm's store answer is the only one the import alone does not decide. `dart.library.io` is also satisfied on macOS, Windows and Linux, none of which has StoreKit or Play Billing, so that arm asks the device question at runtime (`Platform.isIOS` or `Platform.isAndroid`) before handing back a rail, and the same answer tells the driver which store it sells through. The store rail needs configuration the other two do not: see [Configuration](../getting-started/configuration.md).

### The five reads are shared

`BillingServiceWeb` and `BillingServiceIo` both take `BillingReadsOverHttp`, a mixin in a file with no platform import of its own. The reads are identical by nature: they call the same endpoints and decode the same bodies, because the backend is the authority on an entitlement whichever rail sold the subscription.

| Read | Request |
|:-----|:--------|
| `currentEntitlement()` | `GET /billing` |
| `getPlans()` | `GET /billing/plans` |
| `getUsage()` | `GET /billing/usage` |
| `getInvoices({cursor})` | `GET /billing/invoices`, with `cursor` as a query parameter |
| `getPaymentMethod()` | `GET /billing/payment-method` |

A conditional import compiles exactly one arm per target, so no analyzer run and no test on one platform could see two copies of a read disagree. `test/drivers/billing_reads_over_http_test.dart` therefore asserts the structure: the mixin declares all five, neither driver declares one of its own, and the mixin carries no platform seam. A new read goes in the mixin.

The log prefix comes from `runtimeType`, so a line still names the concrete driver that made the call (`[BillingServiceWeb.getUsage]`).

`PaymentsManager` resolves these three functions lazily, the first time a role is read, and `PaymentsServiceProvider.boot()` reads them once so the choice is logged at boot. That is what makes `Payments.web` and `Payments.store` resolve to a real rail or to `null` without a `kIsWeb` check anywhere above the factory. See [Payments Manager](../architecture/payments-manager.md).

<a name="web-driver"></a>
## BillingServiceWeb

Implements both `BillingService` and `WebBillingService` in one class, because the four web writes share a transport and an envelope convention that is not uniform across the endpoints (some bodies arrive wrapped in `data`, some flat). Splitting the reads from the writes into two classes would duplicate that convention in two places.

The writes call `POST /billing/checkout`, `POST /billing/swap` and `POST /billing/cancel`, and `GET /billing/portal`. The two that mint a hosted page (`checkout`, `openPortal`) open it with `LaunchMode.inAppWebView` rather than the facade's default external browser, because a hosted checkout returns the customer to `successUrl` when they are done, and from an external browser that return lands in the browser rather than back in the app. When the launcher refuses to open the page, the call throws a `BillingException` instead of reporting success.

A refusal carries a typed `BillingException.code`: a 422 with `code: product_not_sellable` is `productUnavailable`, and a 402 whose `billing.reason` is `payment_failed` or `payment_requires_action` is `paymentDeclined` or `paymentRequiresAction`. Anything else is `unknown`. See [Rails](./rails.md#errors).

<a name="io-driver"></a>
## BillingServiceIo

Implements `BillingService` only: the five reads, over the same endpoints as the web driver. It carries no purchase-affecting method and no platform-specific throw, because reading an entitlement is honourable on every device: the backend is the authority on it regardless of which rail sold the subscription. The writes live on the rail contracts, which a build that cannot serve them simply does not resolve.

<a name="stub-driver"></a>
## BillingServiceStub

The fallback, reached only where neither `dart.library.html` nor `dart.library.io` applies. Every read throws `UnsupportedPlatformException`, and that is deliberate: there is no assumed network stack to ask on a platform this package has never seen, and a silent empty answer would render as a customer with no subscription, which is a lie about a paying account that a support ticket could not tell from a genuine free tier. Its message names no other way to buy, so a shipped binary never points a customer at a purchase method outside the app.

<a name="extend"></a>
## Overriding a Driver

A role is overridden by registering a factory under its name. The registration evicts any instance already resolved for that role, so the next read builds the override:

```dart
Payments.extend(PaymentsManager.storeRole, () => MyStoreRail());
```

This is the seam a test uses to stand in for a rail without mocking a vendor SDK, and it is how an app replaces the store rail: registering the store role puts your own `StoreBillingService` in front of `RevenueCatStoreService`, which is the supported way to sell through a mediator this package does not ship. See [Rails](./rails.md) and [Payments Manager](../architecture/payments-manager.md).

<a name="gotchas"></a>
## Gotchas

| Mistake | Fix |
|:--------|:----|
| Choosing a rail with `kIsWeb` or `Platform.is*` | Check `Payments.web` and `Payments.store` for `null`; the factory already answered what the build can serve |
| Expecting a store rail on macOS, Windows or Linux because they match `dart.library.io` | `Payments.store` is `null` there; only iOS and Android get `RevenueCatStoreService` |
| Catching `UnsupportedPlatformException` to detect "no billing here" | It comes only from the stub arm, a platform the package has never seen; a missing rail is `null`, not an exception |
| Adding a read to `BillingServiceWeb` or `BillingServiceIo` | Add it to `BillingReadsOverHttp`; the structure test fails when a driver declares its own |
| Registering an override under a name of your own, such as `'sandbox'` | `extend` takes one of the three roles (`billing`, `web`, `store`) and throws a `BillingException` for any other |
| Treating a returned `checkout()` or `openPortal()` as proof the page opened | A launcher that refuses throws a `BillingException`; catch it and tell the customer |

<a name="related-documentation"></a>
## Related Documentation

- [Rails](./rails.md): what each rail's contract promises.
- [Payments Manager](../architecture/payments-manager.md): how the manager resolves and overrides a role.
- [Service Provider](../architecture/service-provider.md): the boot step that reads the factory.
- [Configuration](../getting-started/configuration.md): the store rail's key.
