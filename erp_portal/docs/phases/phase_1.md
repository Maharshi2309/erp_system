# Phase 1 — Architecture and foundation

Status: **Complete, awaiting approval** · 16 Oct 2026

## Delivered
- Architecture, folders and conventions (`docs/architecture.md`, `docs/decisions.md`, `docs/testing_strategy.md`).
- Design tokens from S01: colours, type, spacing, radius and layout, plus the Material theme. IBM Plex is bundled.
- Components:
  - Buttons: 5 variants, 3 sizes, busy and disabled states, keyboard focus ring.
  - Form fields: text field with password toggle, dropdown, error summary.
  - Display: status badge, card, KPI card, page header with breadcrumbs.
  - Data and states: table with in-box horizontal scroll and pagination, empty and error states, skeleton (300 ms delay, reduced motion).
  - Overlays: confirm dialog, side panel (440 px / full width < 600 px, Esc closes), toast.
- Responsive layout: breakpoints, `ResponsivePage`, `ResponsiveGrid`, and an app shell that switches between sidebar, rail and drawer.
- Routing:
  - go_router with a permission-aware guard, re-checked on session change.
  - 404 page; access-denied route.
  - Admin menu filtered by permission.
- Permission model (modules × actions, data scope) and typed failures.
- Demo session (owner / HR admin) with a clearly labelled demo-role switcher. The design-system gallery is at `/dev/design-system`.

## Not in this phase (by design)
- Authentication and real S03 / S72 screens: Phase 2.
- Feature screens: Phases 3–7 (each shows "Not built yet — Phase N").
- Date-range picker and multi-select chips (S02): added in the first phase that uses them (4 or 6).

## Verification (run 16 Oct 2026)

| Check | Result |
|---|---|
| `dart format --set-exit-if-changed` | 0 files changed |
| `flutter analyze` | No issues |
| `flutter test` | 131 passed, 0 failed |
| Line coverage (`--coverage`) | 92.7% (1086 / 1171 lines) |
| `flutter build web --release` | Built; Wasm dry run succeeded |
| Responsive matrix (11 sizes) + 200% text | No overflow at any size |
| Screenshots | `test_screenshots/output/*.png` (7 images) |

Bugs that the tests found and that were fixed:
- Pagination controls overflowed below 360 px. They now wrap.
- Long status-badge labels overflowed. They now truncate with an ellipsis.
- Table rows had a fixed maximum height, which clipped 200% text. They now grow with their content.

## Known limitations
- Nothing is secure: there is no backend and no authentication (D-01).
- Screenshots are rendered by the Flutter test engine, not a browser; shadows show as solid black lines there.
- The app has not yet been opened in a real browser by me. It was verified through the web build and widget tests.
