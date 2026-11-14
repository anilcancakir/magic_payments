# magic_payments example

A Magic app with one page. It boots `PaymentsServiceProvider`, then shows which driver the build resolved, whether `Payments.web` and `Payments.store` exist, and the `payments.driver` config value. A `Read entitlement` button calls `Payments.currentEntitlement()` and shows the answer, or the `BillingException` code when the call fails.

```bash
cd example
flutter create --platforms=web .
flutter run -d chrome
```

`flutter create` adds the platform folder once; it leaves `lib/` and `pubspec.yaml` as they are.

## What works without a backend

On web the page reports the web rail present and the store rail absent. The entitlement read goes to `http://127.0.0.1:8000/api/v1/billing`, so without a backend there it fails and the page shows the `BillingException`. Nothing is faked: a success appears only when a backend answers.

To see a real entitlement, serve the `/billing` endpoints (`magic-starter-laravel` serves them) and set `network.drivers.api.base_url` in `lib/main.dart` to its URL. The backend authenticates the customer, so a real app also registers its auth provider and signs in first; this example sends no token.

## What needs a device or a backend

- The store rail exists only on an iOS or Android build. It needs `payments.revenuecat.public_sdk_key` (RevenueCat's public SDK key, kept out of the repository) and a paying account identified through `StoreIdentitySync`, so this example does not call `purchase`.
- `checkout` and `openPortal` need a backend that creates the hosted pages, so the example does not call them.
