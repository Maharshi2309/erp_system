# Staffline — Employee Management ERP

A Flutter web portal for small and mid-sized organizations. It covers organization and branch setup, employees, attendance, leave, holidays, roles and permissions, reports, notifications and an audit log.

> **Demo build.** There is no backend yet. All data lives in in-memory demo repositories, is seeded with the sample organization *Meridian Textiles*, and resets on reload (decision D-01). Permissions in the app only decide what is shown; a backend must enforce them before production use. See [docs/phases/phase_8.md](docs/phases/phase_8.md).

## Requirements

| Tool | Version used |
|---|---|
| Flutter | 3.44.8 (stable) |
| Dart | 3.12 |
| Browser | Chrome or Edge, for `flutter run -d chrome` |

## Setup

```sh
cd erp_portal
flutter pub get
```

## Run

```sh
flutter run -d chrome                     # web (primary target)
flutter run -d macos                      # desktop, for local checks
flutter run -d chrome --dart-define=SHOW_DEV_TOOLS=false   # hide demo-only tools
```

**Startup speed.** `flutter run` uses debug mode, which is much slower to start and to run than what users get — especially on the web. To judge speed, run release mode:

```sh
flutter run -d chrome --release
```

The demo data layer waits 150 ms per call to imitate a server (`demoLatencyProvider`), so loading states stay visible.

`SHOW_DEV_TOOLS` (default `true`) shows the design-system gallery, the demo-account list on the sign-in page and the role switcher. Turn it off for any build shown to real users.

### Demo accounts

All accounts use the password `Staffline@2026`. Accounts with two-step verification enabled accept the code `482913`.

| Sign in as | Role |
|---|---|
| `ankit@meridiantex.in` | Owner (3 organizations) |
| `hetal.s@meridiantex.in` | HR Admin |
| `jignesh.p@meridiantex.in` | Branch Manager · Surat |
| `mitesh.r@meridiantex.in` | Attendance Manager |
| `aarav.b@meridiantex.in` | Leave Approver |
| `EMP-0229` | Employee · Isha Rathod |
| `admin@staffline.app` | Platform super admin · statistics only |

The demo clock follows the real clock in Asia/Kolkata.

## Build

```sh
flutter build web --release        # output: build/web (static files, any web host)
flutter build macos
flutter build ios --no-codesign
flutter build apk                  # needs the Android SDK licences accepted
```

`flutter build web --wasm` also produces a WebAssembly version that browsers with WasmGC support (current Chrome, Edge, Firefox) load and start faster; other browsers fall back to the JavaScript version automatically. Try it in your browsers before deploying.

The web page shows a "Staffline · Loading…" screen while the app downloads (about 5 MB of app code and 7 MB of rendering engine on the first visit; browsers cache them afterwards). Enable gzip or brotli compression on the web host — it shrinks `main.dart.js` and the `.wasm` files a lot.

**Downloads and uploads.** On the web, downloads go to the browser's Downloads folder. In the macOS, iOS and Android apps a system Save dialog asks where to put the file. Uploads (employee and holiday imports, logo and photos) open the system file picker; the macOS app needs the "user-selected files" entitlement, which `macos/Runner/*.entitlements` already include.

When hosting the web build, serve `index.html` for unknown paths so that deep links such as `/employees/e-13` work.

## Checks

`flutter test` runs everything, including two slow sweeps that press every control on every page for every role (about 10 minutes). For a quick run use `flutter test --exclude-tags sweep`; run the full set before a release.


```sh
dart format --output=none --set-exit-if-changed .
flutter analyze
flutter test                                  # unit, widget and QA (responsive, keyboard)
flutter test --coverage                       # writes coverage/lcov.info
flutter test integration_test -d macos        # the 10 critical journeys on a real device
flutter test test_screenshots --update-goldens  # review images in test_screenshots/output/
```

## Project layout

```text
lib/
├── main.dart
├── app/          router, guards, responsive shell, config, demo-only tools
├── core/         theme tokens, responsive helpers, design-system widgets, permissions, errors
├── shared/       the signed-in session model
└── features/     one folder per area, each with domain/, data/ and presentation/ as needed:
                  auth, organization, onboarding, employees, dashboard, attendance,
                  leave, holidays, roles, audit, notifications, settings, reports
test/
├── unit/         domain rules, guards, permissions, validators
├── widget/       screens and components through the real router
├── qa/           responsive matrix, text scaling, dialogs at 320 px, keyboard
└── test_helpers/ pumpStafflineApp, demo accounts, finders
integration_test/ the critical journeys end to end
test_screenshots/ review screenshots (not part of the regression suite)
docs/             requirements, decisions, architecture, phase reports
```

More detail: [docs/architecture.md](docs/architecture.md), [docs/decisions.md](docs/decisions.md), [docs/testing_strategy.md](docs/testing_strategy.md).
