# Rails

A rail is one way a subscription is sold, and `magic_payments` puts three contracts in front of the rails (`BillingService`, `WebBillingService`, `StoreBillingService`) so an app can render a billing screen without learning any rail's dialect.

- [Quick Reference](#quick-reference)
- [Overview](#overview)
- [The Three Rails](#three-rails)
- [BillingService: Five Reads, Honourable Everywhere](#reads)
- [WebBillingService: the Web Rail](#web)
- [StoreBillingService: The Store Rail](#store)
  - [Product keys, on both rails](#product-keys)
  - [`products()`: the store's own prices](#store-prices)
  - [`store`: which store this is](#store-getter)
  - [`PurchaseContext`](#purchase-context)
  - [`lastChangeTiming`: now or at renewal](#change-timing)
  - [What the store rail refuses](#store-refusals)
  - [Typed errors](#errors)
  - [Keeping the Store Identified](#store-identity)
- [Entitlement Authority Belongs to the Backend](#authority)
- [The Rail and the Platform Are Different Axes](#axis)
- [Gotchas](#gotchas)
- [Related Documentation](#related-documentation)

<a name="quick-reference"></a>
## Quick Reference

```dart
import 'package:magic_payments/magic_payments.dart';

final BillingEntitlement entitlement = await Payments.currentEntitlement();
final WebBillingService? web = Payments.web;
final StoreBillingService? store = Payments.store;
```

| Accessor | Contract | Present on |
|:---------|:---------|:-----------|
| `Payments.billing` (and the five static reads) | `BillingService` | Every build; the reads throw only on the stub arm |
| `Payments.web` | `WebBillingService` | Web builds, `null` elsewhere |
| `Payments.store` | `StoreBillingService` | iOS and Android builds, `null` elsewhere |

<a name="overview"></a>
## Overview

A subscription can be sold by more than one rail: a hosted web checkout, StoreKit on iOS, Google Play Billing on Android. Each has its own vocabulary, its own idea of when a period ends and its own opinion about who may cancel. The package puts one contract in front of them so a consuming app never has to learn a rail's dialect to render a billing screen.

<a name="three-rails"></a>
## The Three Rails

| Rail | Contract | Served by | Platform |
|:-----|:---------|:----------|:---------|
| Hosted web checkout and portal | `WebBillingService` | `BillingServiceWeb` | Web |
| App Store | `StoreBillingService` | `RevenueCatStoreService` | iOS |
| Play Store | `StoreBillingService` | `RevenueCatStoreService` | Android |

`BillingService`, the five reads, sits above all three: it answers on every platform because the backend is the authority on an entitlement regardless of which rail sold it. None of the three contracts extends another, so a build that cannot serve a rail resolves it to `null` rather than declaring a method it would refuse.

<a name="reads"></a>
## BillingService: Five Reads, Honourable Everywhere

```dart
abstract class BillingService {
  Future<BillingEntitlement> currentEntitlement();
  Future<List<Map<String, dynamic>>> getPlans();
  Future<List<UsageStat>> getUsage();
  Future<BillingInvoicesPage> getInvoices({String? cursor});
  Future<PaymentMethod> getPaymentMethod();
}
```

None of these five refuses a platform the package serves. `currentEntitlement()` is the call every billing surface starts from:

```dart
final BillingEntitlement entitlement = await Payments.currentEntitlement();

if (entitlement.subscribed) {
  // Offer "Manage subscription" according to entitlement.manageVia.
}
```

`Payments` forwards each of the five reads directly as a static method of the same name. `getPlans()` returns each tier's row verbatim rather than decoded into a shared type: a plan's prices and feature bullets are the vendor's product, not a payment concept, and the consumer already owns the type it wants to decode them into. `getPaymentMethod()` reports a rail outage as a `PaymentMethod` with every field null; gate the copy on `PaymentMethod.available`, not on a null `last4`.

<a name="web"></a>
## WebBillingService: the Web Rail

```dart
abstract class WebBillingService {
  Future<BillingCheckoutSession> checkout({
    required String productKey,
    required String successUrl,
    required String cancelUrl,
  });
  Future<void> swap({required String productKey});
  Future<void> cancel();
  Future<String> openPortal({String? returnUrl});
}
```

These four methods change what the customer is paying for, so they live off the read contract entirely. The package never talks to a payment vendor from the app: each call goes to your backend, which owns the vendor relationship, and `checkout` and `openPortal` open the hosted page your backend returns. `Payments.web` resolves to `null` off a web build; a caller checks for the rail before it renders an upgrade button, rather than rendering one and catching a refusal:

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

One product key names the tier and the cycle together (see [Product keys](#product-keys)). A tier is not a price: a vendor selling `pro` monthly and again at a discounted annual rate has two products, and when tier and cycle travelled as two words a call that lost the second let the backend pick a price while the screen showed the other. A single key cannot be half-sent. `checkout` and `swap` send it as `product`; the backend resolves the price from the key and refuses with a 422 when it has none mapped, which is how an adopter learns that rather than having a customer quietly charged the wrong figure. That 422 carries `code: product_not_sellable`, and the driver throws it as a `BillingException` with `BillingErrorCode.productUnavailable` and the backend's own message; any other 422 stays `unknown`.

A plan change that is charged at once can also be refused with a 402: the driver maps a `payment_failed` reason to `BillingErrorCode.paymentDeclined` and a `payment_requires_action` reason to `BillingErrorCode.paymentRequiresAction`, and nothing changes in either case.

A cancellation on this rail is normally end-of-period, not immediate: the entitlement it leaves behind still grants until `BillingEntitlement.currentPeriodEnd`. Re-read the entitlement rather than assuming the call revoked anything.

<a name="store"></a>
## StoreBillingService: The Store Rail

```dart
abstract class StoreBillingService {
  Future<void> identify(String appUserId);
  Future<bool> purchase(String productKey, {PurchaseContext? context});
  Future<Map<String, StoreProductOffer>> products(List<String> productKeys);
  Future<bool> restore();
  Future<void> openStoreManagement();
  StoreChangeTiming? get lastChangeTiming;
  ManageVia get store;
}
```

`RevenueCatStoreService` implements it, and `Payments.store` is non-null on iOS and Android. It stays `null` on web, on desktop and on the fallback arm, so a purchase affordance is gated on `Payments.store != null` and not on a platform check of your own.

> [!WARNING]
> Non-null does not mean configured. The driver reads `payments.revenuecat.public_sdk_key` the first time it needs the SDK and throws a `BillingException` with `BillingErrorCode.notConfigured` when that key is blank or absent, because whether a device has a store and whether you have supplied credentials for it are two different questions. See [Configuration](../getting-started/configuration.md).

The contract makes one non-promise, and it is the whole reason the store rail is separate:

**A `true` from `purchase()` or `restore()` says the store reported a completed transaction. It says nothing about what `currentEntitlement()` will answer immediately afterwards.** A store purchase is asynchronous, and the rail's own webhook is the authority on the entitlement, not the device that tapped Buy. The backend may not have been told yet by the time the purchase call returns.

```dart
final StoreBillingService? store = Payments.store;
if (store != null) {
  // The rail cannot see a subscription billed on the web.
  final BillingEntitlement held = await Payments.currentEntitlement();

  if (held.manageVia != ManageVia.portal) {
    final bool bought = await store.purchase('pro_annual');
    if (bought) {
      // The store is done. The entitlement may not have caught up yet.
      // Treat a stale answer as "not yet", never as a failure.
      await Payments.currentEntitlement();
    }
  }
}
```

Reading `purchase()`'s `true` as an entitlement grant is the bug this contract exists to prevent on the store rail. The web rail has the same gap, since its entitlement also follows the vendor's webhook, but it hands back nothing to misread: `checkout` returns a `BillingCheckoutSession`, and `swap` and `cancel` return nothing once the backend has accepted the request. Re-read `currentEntitlement()` after any of them (see [Entitlement Authority](#authority)).

<a name="product-keys"></a>
### Product keys, on both rails

`purchase`, `checkout` and `swap` all take the same thing: the vendor's own catalogue key, such as `'pro_annual'`, which is the `key` of an entry in a `getPlans()` row's `products` list. It is never a store product id and never a payment vendor's price id. Which store product or price a key maps to belongs to the rail's catalogue (on the store rail the key is the RevenueCat package identifier, searched in the current offering first and then the rest; on the web rail, the backend's price table), so adding or repricing a product needs no client release. A product's `ProductType` (`subscription`, `consumable`, `nonConsumable`, `physical`) says what a purchase leaves behind; only a subscription key carries a cycle.

<a name="store-prices"></a>
### `products()`: the store's own prices

```dart
final Map<String, StoreProductOffer> offers = await store.products(
  <String>['pro_monthly', 'pro_annual'],
);
final StoreProductOffer? annual = offers['pro_annual'];
```

A store build renders the store's figures, not the catalogue's, because the store decides currency, tax and rounding and its sheet will show them. A `StoreProductOffer` carries `priceString` (already localised), `currencyCode`, `price`, an ISO `subscriptionPeriod` and the intro-price fields (`introPrice`, `introPriceString`, `introPeriod`). A key the store has no product for is absent from the map; render that product as unavailable rather than guessing a price. `products()` resolves through the same offering packages `purchase` uses, so a key it prices is a key a purchase can buy.

`introEligible` says whether this customer may take the intro offer, and defaults to `false`: show intro copy ("Free for 14 days, then ...") only when it is `true`, and the plain price otherwise. An `introPrice` alone says the product has an offer, not that the customer may take it. The rule is per store, read off `store`:

| Store | How `introEligible` is decided |
|:------|:-------------------------------|
| App Store | One SDK read of the store product ids that carry an intro price. Only a definite `eligible` is `true`; `unknown`, `ineligible` and no offer are `false`. |
| Play | No read: the SDK answers unknown for everything on Android. A present intro price is treated as eligible, because Play only offers what the account may take. Unverified against a real account. |

A failed eligibility read is logged and leaves every `introEligible` `false`; the prices still render.

<a name="store-getter"></a>
### `store`: which store this is

`StoreBillingService.store` answers `ManageVia.appStore` or `ManageVia.playStore`. Compare it with `BillingEntitlement.manageVia` to tell a subscription this store can change from one another rail sold, without asking the running platform.

<a name="purchase-context"></a>
### `PurchaseContext`: telling an upgrade from a downgrade

A store knows products, not tiers. When the customer already holds a subscription, pass the facts the rail needs, distilled from the catalogue you already read:

```dart
await store.purchase(
  'business_annual',
  context: const PurchaseContext(
    tierOrder: <String>['free', 'pro', 'business'],
    tierOfProduct: <String, String>{'pro_monthly': 'pro', 'business_annual': 'business'},
    tierOfStoreProduct: <String, String>{
      'pro_sub:monthly': 'pro',
      'legacy_pro_sub:monthly': 'pro',
      'com.app.pro.monthly': 'pro',
    },
  ),
);
```

`tierOfStoreProduct` maps a store product id to its tier, and it is the only way the rail can rank a grandfathered product: one the customer still holds but no offering sells any more, so it has no catalogue key. Build it from every plan row's `products[].store_ids` (`app_store` and `play`), including the products marked not sellable. A Play id is `subscriptionId:basePlanId`; the rail matches the full id first and then the bare subscription id, the latter only when every id under that subscription names one tier. It defaults to empty, which refuses a Play change from a product nothing names rather than guessing its tier.

On Google Play the context decides the replacement mode of a product change:

| Change | Replacement mode | `lastChangeTiming` |
|:-------|:-----------------|:-------------------|
| same subscription, longer period | `chargeFullPrice` | `immediate` |
| same subscription, same or shorter period | `withoutProration` | `immediate` |
| other subscription, higher tier, price per day rises | `chargeProratedPrice` | `immediate` |
| other subscription, higher tier, price per day does not rise | `chargeFullPrice` | `immediate` |
| other subscription, same or lower tier | `deferred` | `atRenewal` |

Play accepts a prorated charge only when the price per unit of time rises, so the rail compares `price / period in days` of the held and the target product: pro monthly at 30 to business annual at 300 is 1.00 a day to 0.82 a day, and is charged in full. A grandfathered held product has no price or period the rail can read, so an upgrade from it is charged in full and a base-plan switch on its own subscription is refused (`unmappedActiveProduct`). Without a context a change between subscriptions is refused rather than guessed.

The App Store rail passes no change at all: StoreKit moves a subscription inside its group on its own, so a grandfathered product never blocks the purchase there.

<a name="change-timing"></a>
### `lastChangeTiming`: now or at renewal

`purchase` keeps its `Future<bool>`. Right after a purchase that answered `true`, read `store.lastChangeTiming` to tell the customer when the change lands:

```dart
// `context` is the PurchaseContext built in the sample above.
if (await store.purchase('pro_monthly', context: context)) {
  final String? notice = switch (store.lastChangeTiming) {
    StoreChangeTiming.immediate => 'Your plan has changed.',
    StoreChangeTiming.atRenewal => 'Your plan changes at your next renewal.',
    null => null,
  };
}
```

On Play it follows the replacement mode in the table above (`deferred` is `atRenewal`, every other mode `immediate`). On the App Store it follows the subscription group's levels: a higher level applies at once, a lower level or the same level at another duration at the next renewal. `null` means there is nothing to announce: a fresh purchase, a dismissed or refused one, or a change the rail cannot rank (no context, a held product no tier names, more than one held App Store product).

<a name="store-refusals"></a>
### What the store rail refuses

`purchase` and `restore` refuse, rather than guess, in these cases. Each throws a `BillingException` with a typed code (see [Typed errors](#errors)):

- **Identity.** Nothing was identified (`notIdentified`), or the SDK's `appUserID` is not the id `identify()` bound (`identityMismatch`). A purchase attributed to another account is one the backend cannot give to the right customer.
- **The other store sells the subscription** (`managedElsewhere`). The rail reads the store product ids RevenueCat reports active, and a subscription purchase is refused when one of them belongs to the other store (a Play `subscriptionId:basePlanId` on the App Store rail, an App Store id on the Play rail), because a second subscription here would charge the customer twice. A one-off product is still sold beside it.
- **A Play product no change can be computed against** (`unmappedActiveProduct`). The account holds a Play product that neither the offerings nor `tierOfStoreProduct` rank, a grandfathered product on the subscription being switched, or more than one Play subscription at once.

A RevenueCat promotional grant (an `rc_promo_...` id in the active subscriptions, issued from the RevenueCat dashboard) is no store's subscription, so it takes part in none of these checks.

The rail does not refuse on a web subscription. The web rail is billed through your backend, so it is not among the products RevenueCat reports active, and the store rail cannot see it. Gate the store's purchase affordance on `BillingEntitlement.manageVia` yourself: when it is `ManageVia.portal`, the customer changes that subscription on the web (see [The Rail and the Platform Are Different Axes](#axis)).

On Android a product change is passed to Play with the proration the context implies; the customer sees Play's own sheet.

<a name="errors"></a>
### Typed errors: `BillingException.code`

Switch on `BillingException.code`, never on `message`, which is prose that differs per rail and per locale. The code is client-side only and is never encoded to the wire; a driver translates a producer's own refusal code into one (`product_not_sellable` is `productUnavailable`). A failure no driver named is `unknown`.

| `BillingErrorCode` | Meaning |
|:-------------------|:--------|
| `notConfigured` | no `public_sdk_key` in this build |
| `notIdentified` | no paying account identified before a purchase |
| `identityMismatch` | the SDK is bound to a different account than the one asking |
| `managedElsewhere` | the other store sells a subscription the customer holds (store rail only) |
| `unmappedActiveProduct` | an active Play product cannot be ranked, so no replacement mode is safe |
| `productUnavailable` | the rail has no product for the key, or the backend will not sell it (`product_not_sellable`) |
| `pending` | the store has not settled it (parental approval, deferred payment); not a failure to retry |
| `receiptInUse` | the receipt belongs to another paying account |
| `alreadyOwned` | the customer already holds the product |
| `paymentDeclined` | a plan change charged at once was declined by the card; nothing changed (web rail) |
| `paymentRequiresAction` | a plan change charged at once needs the card holder to confirm (3D Secure); nothing changed (web rail) |
| `network` | the request or its answer never arrived |
| `store` | the store refused for a reason none of the above names |
| `unknown` | no cause named |

A customer dismissing the sheet is `false` from `purchase`, not an exception.

<a name="store-identity"></a>
### Keeping the Store Identified

The id passed to `identify()` is what the rail's webhook attributes a purchase to, so the rail has to be re-identified whenever the paying subject changes: on login, on a session restore, and on every switch of the subject (a team switch, where teams pay). `StoreIdentitySync` owns the when; you supply the who:

```dart
// Who pays is your answer: a team here, a user elsewhere. `User` and
// `switchTeam` stand for your app's own model and action.
StoreIdentitySync.billableId = () => User.current.currentTeam?.id?.toString();
StoreIdentitySync.attach();

// attach() only adds a listener. `Magic.init` has already restored the
// session by the time it returns, so a returning user raises no further auth
// change; identify the restored subject once, explicitly.
await StoreIdentitySync.syncNow();

// A switch of the paying subject identifies explicitly once it succeeded,
// because the auth change it causes may still carry the previous subject.
if (await switchTeam(teamId)) {
  await StoreIdentitySync.syncNow();
}
```

Run the first three calls after `await Magic.init(...)`, which restores the stored session when a user factory is registered. Without the `syncNow()`, a returning user's store rail stays unidentified and `purchase` throws `notIdentified` until the next auth change. The alternative is to call `attach()` from a provider that boots before `AuthServiceProvider` (providers boot in the order of `app.providers`, and the restore bumps `Auth.stateNotifier`), which makes the restore itself trigger the sync.

- `attach()` listens to `Auth.stateNotifier` and syncs on every change after it, without syncing on its own; calling it twice listens once. `detach()` stops listening and forgets what was identified.
- A build without a store rail, and a session without a subject (`null` or an empty id), identify nothing. A signed-out session unbinds nothing either: the contract has no logout, and the next sign-in overwrites the binding.
- Syncs run one at a time in call order, and each reads the subject when its turn comes. A switch that lands while an identify is in flight identifies the newer subject after it, never alongside it, so the rail ends on the newer subject whatever order the vendor SDK finishes its calls in.
- The same id twice in a row identifies once, including two overlapping syncs. The guard resets when the id goes absent, so signing out and back in as the same subject identifies again.
- A `BillingException` from the rail is logged at error level and not thrown, since the login or switch that prompted the sync already succeeded; the next sync retries that id.
- `billableId` has no default. While it is unset nothing is identified, and one debug line says so.

<a name="authority"></a>
## Entitlement Authority Belongs to the Backend

**Your backend, not this package, decides who is entitled to what.** Every method on every contract here is a client of that decision, never a maker of it:

- `WebBillingService.checkout`, `.swap` and `.cancel` ask the backend to change something and let its own webhook project the result into the entitlement it serves back.
- `StoreBillingService.purchase` and `.restore` hand the customer to the App Store or Play Store and report only what the store said, not what the backend has recorded.
- `BillingService.currentEntitlement` is the one call that reads the backend's own answer, and it is the only source of truth this package recognises.

A client that grants a feature locally on a `true` from a purchase or a checkout call has built an entitlement of its own that can disagree with the backend's. Always re-read `currentEntitlement()` after a write, and treat the write's own boolean or session as a hint that something happened, never as the grant itself.

<a name="axis"></a>
## The Rail and the Platform Are Different Axes

A subscription bought on an iPhone is still managed in the App Store when the customer opens the web app. The rail that sold a subscription and the platform the app happens to be running on are independent facts, and conflating them is the mistake this package exists to prevent.

So a consumer branches its management affordances on `BillingEntitlement.manageVia` (`ManageVia.portal`, `.appStore`, `.playStore` or `.none`), never on `kIsWeb` or `Platform.is`:

```dart
// `openUrl` stands for your app's own URL launcher.
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
    // Nowhere to send the customer: no rail, an operator grant, or an unknown rail.
    break;
}
```

The store case cannot be a null-aware call. A customer who bought on a phone and opens the web app still has a store `manageVia`, and `Payments.store` is `null` there, so `Payments.store?.openStoreManagement()` would do nothing and tell the customer nothing. `openStoreManagement()` exists on iOS and Android builds only. Without the rail, use `BillingEntitlement.manageUrl` when the backend sent one; when it did not, the package gives you nothing to open, so say which store manages the subscription and render no link. `manageUrl` is `null` for `portal` by design: the portal page is minted by `openPortal()` on web builds.

On a non-web platform, never render a link, URL or call to action pointing at web checkout or the web portal. App Review Guideline 3.1.3(a) restricts steering a customer outside the app to another purchase method, and `manageVia` being the same value on every platform for the same rail is what makes that easy to honour: there is nothing to override per platform, only per rail.

<a name="gotchas"></a>
## Gotchas

| Mistake | Fix |
|:--------|:----|
| Granting a feature on the `true` from `purchase()` or on a returned `checkout()` | Re-read `Payments.currentEntitlement()`; a store purchase is asynchronous and the backend's answer is the grant |
| Choosing a management screen with `kIsWeb` or `Platform.is*` | Branch on `BillingEntitlement.manageVia`; a subscription is managed where its rail sold it |
| Treating `Payments.store != null` as "the store rail is ready" | It only says the device has a store; a blank `public_sdk_key` throws `BillingErrorCode.notConfigured` at purchase time |
| Calling `purchase()` before anything identified the paying account | Set `StoreIdentitySync.billableId`, call `attach()`, then `await StoreIdentitySync.syncNow()`; otherwise the call throws `notIdentified` |
| Switching on `BillingException.message` | Switch on `BillingException.code`; the message is prose that differs per rail |
| Showing intro-offer copy because `introPrice` is set | Gate it on `introEligible`, which defaults to `false` |

<a name="related-documentation"></a>
## Related Documentation

- [Drivers](./drivers.md): which build resolves which rail.
- [Payments Manager](../architecture/payments-manager.md): how `Payments.web` and `Payments.store` resolve.
- [Configuration](../getting-started/configuration.md): the store rail's SDK key.
- [Installation](../getting-started/installation.md): adding the package to an app.
