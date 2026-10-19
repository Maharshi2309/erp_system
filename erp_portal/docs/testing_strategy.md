# Testing Strategy

| Layer | Location | What it covers | Command |
|---|---|---|---|
| Unit | `test/unit/` | Pure logic: breakpoints, grid columns, colour contrast (WCAG AA), permissions, failure messages, route guards, menu filtering. From later phases: validators, durations, balances, progress %. | `flutter test test/unit` |
| Widget | `test/widget/` | Components (states, semantics, keyboard), routing through the real router, the shell at every breakpoint, 200% text | `flutter test test/widget` |
| QA | `test/qa/` (Phase 8) | Every page per role at the 9 matrix sizes and intermediate widths, 130% and 200% text, window resizing, dialogs and side panels at 320 px, keyboard (Tab order, Enter, Escape, focus ring) | `flutter test test/qa` |
| Integration | `integration_test/` | The 10 critical journeys end to end on a real device (macOS; Chrome when installed) | `flutter test integration_test -d macos` |
| Screenshots | `test_screenshots/` | Review images with real fonts, written to `test_screenshots/output/`. Not part of the regression suite. | `flutter test test_screenshots --update-goldens` |
| Backend | — | Tenant isolation and authorization. **Not possible until a backend exists (Q-01).** | — |

## Responsive matrix

Every phase runs its screens at 320×568, 375×667, 390×844, 430×932, 767, 768×1024, 1023×768, 1024×768, 1280×800, 1440×900 and 1920×1080. It asserts that no layout errors occur (overflow fails the test) and that the expected shell is used. Large text (200%) is checked on a phone.

## Rules

- Every phase runs, before asking for approval: `dart format --output=none --set-exit-if-changed lib test`, `flutter analyze`, `flutter test`, and `flutter build web`.
- Tests use the demo data source; there are no network calls.
- Looping animations are disabled in tests through the reduce-motion setting, so `pumpAndSettle` finishes.
- Phase reports state test counts as actually run. Coverage is reported only when measured.
