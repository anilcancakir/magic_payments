# CLI Reference

`magic_payments` adds `payments:install` to scaffold, `payments:configure` to change a value afterwards and `payments:doctor` to report on a project to `dowel`.

- [Quick Reference](#quick-reference)
- [Overview](#overview)
- [install](#install)
- [configure](#configure)
- [doctor](#doctor)
- [MCP Exposure](#mcp)
- [Gotchas](#gotchas)
- [Related Documentation](#related-documentation)

<a name="quick-reference"></a>
## Quick Reference

| Command | Flags | Writes files |
|:--------|:------|:-------------|
| `payments:install` | `--dry-run`, `--force` | Yes: the config, `lib/config/app.dart`, `lib/main.dart` |
| `payments:configure` | `--show`, `--driver=<mode>` | Yes: the `driver` value in `lib/config/payments.dart` |
| `payments:doctor` | `--verbose`, `--json` | No |

<a name="overview"></a>
## Overview

Every command runs through `dowel`:

```bash
dart run magic:dowel payments:doctor
```

The `payments:*` commands exist once `dowel` has registered the plugin's provider, which is what `plugin:install` does:

```bash
flutter pub add magic_payments
dart run magic:dowel plugin:install magic_payments
```

`lib/cli.dart` is a separate entry point from `lib/magic_payments.dart` deliberately, so an app that never touches the CLI does not pay for the command tree in its runtime build; nothing under it imports Flutter or `dart:ui`.

<a name="install"></a>
## install

Sets up the package in a consuming app: it publishes `lib/config/payments.dart`, registers `PaymentsServiceProvider` in `lib/config/app.dart` and wires `paymentsConfig` into `configFactories` in `lib/main.dart`. The whole plan is the bundled `install.yaml`; the command has nothing of its own to add.

```bash
dart run magic:dowel payments:install
dart run magic:dowel payments:install --dry-run
dart run magic:dowel payments:install --force
```

`--dry-run` stages the operations and writes nothing. Running it again converges on the same edits instead of duplicating them. A config file you edited by hand no longer matches the install record, so the run is refused and lists the files; `--force` overwrites them, and is your decision rather than a default.

<a name="configure"></a>
## configure

Reads or changes the one value the published config carries, without going near the installer, so a hand-edited file is never treated as a conflict.

```bash
dart run magic:dowel payments:configure --show
dart run magic:dowel payments:configure --driver=platform
```

`--driver` accepts `platform` and nothing else; any other value exits 1 and writes nothing, because the runtime would log an error about it and ignore it. A driver of your own is registered in code with `Payments.extend(role, factory)` (see [Payments Manager](../architecture/payments-manager.md)). The command refuses when `lib/config/payments.dart` does not exist and points you at `payments:install`.

<a name="doctor"></a>
## doctor

A read-only health check over the installation and configuration state. It validates what is on disk and mutates nothing.

```bash
dart run magic:dowel payments:doctor
dart run magic:dowel payments:doctor --verbose
dart run magic:dowel payments:doctor --json
```

Each line of the report reads a file in your project and can come back false, then the config state it actually read:

```
Magic Payments, doctor report
==================================================

Dependency declared: ✓
Dependency resolved: ✓
Config published: ✓
Provider registered: ✓
Config factory wired: ✓

Config state:
  driver: 'platform'
  store rail key: blank
    note: iOS and Android builds read 'payments.revenuecat.public_sdk_key' and
    throw at purchase time without it. Web and desktop builds never read it.

✓ Every check passed.
```

The command exits 0 when every check passes and 1 otherwise. `--verbose` adds the path and the requirement behind each line, so a false line names the file to open.

### `--json`: the report for an agent

`--json` prints exactly one JSON object and nothing else (no banner, no prose), and exits with the same code as the human report: 0 when no check is an `error`, 1 otherwise.

```json
{
  "ok": false,
  "checks": [
    {"id": "dependency_declared", "status": "ok", "message": "magic_payments is declared in pubspec.yaml"},
    {"id": "config_factory_wired", "status": "error", "message": "lib/main.dart does not pass paymentsConfig to configFactories", "fix": "run `dart run magic:dowel payments:install`"},
    {"id": "store_rail_key", "status": "warn", "message": "payments.revenuecat.public_sdk_key: blank", "fix": "set payments.revenuecat.public_sdk_key in lib/config/payments.dart; ..."}
  ]
}
```

| `id` | What it reads |
|:-----|:--------------|
| `dependency_declared` | `pubspec.yaml` lists `magic_payments` |
| `dependency_resolved` | `.dart_tool/package_config.json` carries it |
| `config_published` | `lib/config/payments.dart` exists |
| `config_valid` | that file declares the `payments` root and a served `driver` |
| `provider_registered` | `lib/config/app.dart` registers `PaymentsServiceProvider` |
| `config_factory_wired` | `lib/main.dart` passes `paymentsConfig` to `configFactories` |
| `store_rail_key` | the store rail's `public_sdk_key`, as `present`, `absent` or `blank` |

`status` is `ok`, `warn` or `error`, and `fix` appears on every check that is not `ok`. `store_rail_key` can only be `ok` or `warn`, so it never turns `ok` false. A key is only ever reported as present, absent or blank; its value is never read into the output, so the JSON is safe to paste into a ticket or hand to an agent.

### The store rail key is reported, not enforced

The human report says `declared` where the JSON says `present`; the other two words are `absent` and `blank`, and none of them fails the command.

- `absent` means no `public_sdk_key` was published at all.
- `blank` means the key is there with every platform arm empty, which is the state a project ships in first.
- `declared` (`present` in `--json`) means at least one arm carries a value. One is enough: which arms an app needs is not this command's business.

That is deliberate. The command runs on your laptop and cannot know which platform you will ship, so a web-only or desktop-only app is correct without the key and would turn red for no reason. The report carries the consequence instead: the store driver throws at purchase time when the key is missing.

The value is read as text, with comments stripped first, and never evaluated. The published stub resolves the key per platform through `defaultTargetPlatform` (see [Configuration](../getting-started/configuration.md)), so what sits on disk is Dart source rather than a literal. Stripping comments matters: a reminder such as `// TODO: paste the key from the RevenueCat dashboard` is not mistaken for a key.

### What it deliberately does not report

It does not say which rail your builds can serve. That answer lives behind a conditional import, so the only value a pure-Dart CLI process could read is the one for its own compilation, which is the `dart:io` arm every time regardless of what you build for. Printing it would be a confident wrong answer, so it is absent rather than approximated. See [Drivers](./drivers.md).

<a name="mcp"></a>
## MCP Exposure

Only `doctor` is exposed as an MCP tool, `payments_doctor`, with the same two options (`verbose` and `json`). `install` and `configure` both mutate a consuming project's files, and a mutating command is deliberately absent from the MCP surface: an agent can ask whether a project's billing setup is healthy, but installing or reconfiguring it stays a command a human runs.

<a name="gotchas"></a>
## Gotchas

| Mistake | Fix |
|:--------|:----|
| Running `payments:install` before the plugin is registered | Run `dart run magic:dowel plugin:install magic_payments` first; the `payments:*` commands come from the provider it registers |
| Running `payments:install` after adding the dependency to `pubspec.yaml` by hand, without `flutter pub get` | Run `flutter pub get`; the install finds its stub through `.dart_tool/package_config.json` and stops with a message saying so |
| Re-running `payments:install` to change a value you edited by hand | Use `payments:configure`; install refuses a file that no longer matches its record, and `--force` discards your edit |
| `payments:configure --driver=<rail name>` | Exits 1: the only mode is `platform`; register your own driver in code with `Payments.extend` |
| Reading a green `doctor` as "the store rail is configured" | A blank `public_sdk_key` is a warning and still exits 0; check the `store rail key` line or the `store_rail_key` check |
| Expecting `doctor` to say which rails a build serves | It cannot: the answer is a compile-time import. Ask `Payments.web` and `Payments.store` at runtime |

<a name="related-documentation"></a>
## Related Documentation

- [Installation](../getting-started/installation.md): adding the package and what `payments:install` leaves behind.
- [Configuration](../getting-started/configuration.md): the keys `doctor` reads.
- [Drivers](./drivers.md): why `doctor` cannot report rails.
- [Service Provider](../architecture/service-provider.md): what the registered provider does at boot.
