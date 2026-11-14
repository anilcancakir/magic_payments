# Payments Manager

`PaymentsManager` is the singleton behind the `Payments` facade: it resolves the three roles (`billing`, `web`, `store`) from the build's factory or from an override registered with `extend`.

- [Quick Reference](#quick-reference)
- [Singleton Lifecycle](#singleton)
- [The Three Roles](#roles)
- [Rail Resolution: web and store](#rails)
- [extend(): Overriding a Role](#extend)
- [Facade Delegation](#facade)
- [Related Documentation](#related-documentation)

<a name="quick-reference"></a>
## Quick Reference

| Member | Answers | When it is `null` |
|:-------|:--------|:------------------|
| `billing` | `BillingService`, the five reads | Never |
| `web` | `WebBillingService?`, the hosted checkout and portal | A build that cannot serve the web rail |
| `store` | `StoreBillingService?`, the store purchase | A build that cannot serve a store |
| `extend(role, factory)` | Registers an override for a role | n/a |
| `forgetDrivers()` | Drops every override and every resolved instance | n/a |

The roles are `PaymentsManager.billingRole`, `PaymentsManager.webRole` and `PaymentsManager.storeRole`; `PaymentsManager.roles` is the closed set.

<a name="singleton"></a>
## Singleton Lifecycle

`PaymentsManager` is a process-level singleton: a private constructor behind a `factory` that always returns the same instance.

```dart
class PaymentsManager {
  static final PaymentsManager _instance = PaymentsManager._internal();

  factory PaymentsManager() => _instance;

  PaymentsManager._internal();
}
```

`Payments`, the facade, resolves the same instance, and so does `app.make<PaymentsManager>('payments')`, so an override registered through one is visible through the others.

<a name="roles"></a>
## The Three Roles

A role is filled by a consumer's override when there is one, otherwise by the build's conditional-import factory (see [Drivers](../basics/drivers.md)). Each role is resolved the first time it is read and held after that.

`billing` carries the five reads. `Payments` forwards each one as an explicit static method of the same name:

```dart
import 'package:magic_payments/magic_payments.dart';

final BillingEntitlement entitlement = await Payments.currentEntitlement();
final List<Map<String, dynamic>> plans = await Payments.getPlans();
final List<UsageStat> usage = await Payments.getUsage();
final BillingInvoicesPage invoices = await Payments.getInvoices();
final PaymentMethod method = await Payments.getPaymentMethod();
```

The manager always has some `BillingService`, because every arm of the factory returns one. On a platform the package has never seen that service is the stub, and each of its reads throws `UnsupportedPlatformException`: a refusal a support ticket can read, rather than an empty answer that would render as a customer with no subscription.

<a name="rails"></a>
## Rail Resolution: web and store

The manager exposes the two rails from the same factory rather than from a platform check:

```dart
WebBillingService? get web;
StoreBillingService? get store;
```

`Payments.web` and `Payments.store` forward these directly. Either can be `null`, and that is the whole availability mechanism: a caller checks the rail before it renders an affordance, instead of rendering one and catching a refusal.

```dart
final WebBillingService? web = Payments.web;
if (web != null) {
  await web.checkout(
    productKey: 'pro_annual',
    successUrl: 'https://example.com/billing?checkout=success',
    cancelUrl: 'https://example.com/billing?checkout=cancel',
  );
}
```

There is no second way to ask the same question: no `isWeb` getter, no `kIsWeb` check inside the manager. A rail that is absent is not cached, so asking again costs nothing. See [Rails](../basics/rails.md) for what each rail's contract promises.

<a name="extend"></a>
## extend(): Overriding a Role

`extend(role, factory)` registers a factory for one role and evicts any instance already resolved for it, so the next read builds the override. It is the seam a test uses to stand in for a rail without mocking a vendor SDK, and the way an app supplies a rail this package does not ship.

```dart
Payments.extend(PaymentsManager.storeRole, () => MyStoreRail());
```

- An unknown role throws a `BillingException` at once, because an override under a misspelt role is one nothing would ever read.
- The factory is not called by `extend`. Its result is type-checked when the role is first read, and a wrong type throws a `BillingException` naming the role.
- `forgetDrivers()` clears every override and every resolved instance. Call it between tests: the manager is a `static final` that outlives a container reset.

<a name="facade"></a>
## Facade Delegation

`Payments` carries no logic of its own; every member forwards to the manager:

```dart
class Payments {
  Payments._();

  static PaymentsManager get manager => PaymentsManager();

  static BillingService get billing => manager.billing;
  static WebBillingService? get web => manager.web;
  static StoreBillingService? get store => manager.store;

  static Future<BillingEntitlement> currentEntitlement() =>
      billing.currentEntitlement();

  // getPlans, getUsage, getInvoices, getPaymentMethod, extend and
  // forgetDrivers follow the same shape.
}
```

<a name="related-documentation"></a>
## Related Documentation

- [Service Provider](./service-provider.md): where the manager is bound and its driver is resolved at boot.
- [Rails](../basics/rails.md): the three contracts the roles carry.
- [Drivers](../basics/drivers.md): which build resolves which implementation.
