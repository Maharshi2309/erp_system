# Phase 0 — Reference Design Audit

Status: **Draft for approval** · Audited 15 Oct 2026

## 1. Sources inspected

| Source | What it is | Access | Authority |
|---|---|---|---|
| Design canvas `https://claude.ai/artifact/3M6qT23orpzhrqn19vRb5Y` ("Employee Management ERP", product name **Staffline**) | 100 artboards (`project/*.dc.html`) plus `canvas.json` index, version `1792050548-0c43` | **Fully accessible.** Every board's source was downloaded and read: markup, labels, inline links and the JavaScript behaviour of all 30 interactive boards. | Source of truth for UI and user flow |
| *Staffline — Design and workflow guide* (PDF, 126 pp., 14 Oct 2026) | Narrative of the 98 screens, 16 stages, roles, onboarding rules, design system | Attached in chat | Explains intent of the canvas; where it disagrees with the canvas source, the canvas wins (see §5) |
| *Employee Management ERP — Requirements Document v1.0* (PDF, 17 pp., 13 Oct 2026) | PRD: scope, roles, rules, data model, acceptance criteria | Found at `~/Downloads/Employee_Management_ERP_Requirements_Document.pdf` | Source of truth for business rules, roles, permissions |

**Nothing in the reference was inaccessible.** The 19 "Ob…" scenario boards and the 4 small-screen onboarding boards are copies of one component (`OrgOnboarding.dc.html`) opened with a `scenario` property (`live`, `noOrg`, `createOrg`, … `loading`); they were audited through that single source, which contains every state.

How the boards were inspected: static reading of the HTML/JS source. The prototype was **not executed in a browser** in this phase, so pixel measurements in the screen inventory come from the source styles, not from rendered screenshots. The PDF guide's screenshots were used to confirm visual layout.

## 2. Existing project

| Item | Finding |
|---|---|
| Location | `/Users/maharshi/Documents/ERP System/erp_portal` (not a git repository) |
| State | **Unmodified `flutter create` template** — counter app in `lib/main.dart`, counter widget test |
| Flutter / Dart | Flutter 3.44.8 stable · Dart 3.12.2 (`sdk: ^3.12.2`) |
| Platforms scaffolded | android, ios, web, macos, linux, windows |
| Dependencies | `cupertino_icons` only; dev: `flutter_test`, `flutter_lints ^6.0.0` |
| Routing / state / API / auth / DB | None |
| Tests | Template counter test only |
| Reusable widgets / tokens | None |

Conclusion: there is no architecture to preserve. Phase 1 starts from a clean slate; the template `main.dart` and counter test will be replaced.

## 3. What the reference contains

- **98 screens in 16 stages** (canvas rows), plus a flow-map board. Full list: `screen_inventory.md`.
- **One live, fully interactive flow:** Onboarding v2 (create org → owner profile → first branch with weekly hours → per-branch progressive checklist → mark ready). Its complete state model, validation messages and progress formula are documented in `navigation_flows.md` §3.
- **29 other interactive boards** with real behaviour (two-step sign-in with lockout, email code with resend timer, punch with server-confirmation, leave approve/reject with mandatory reason, correction with reason, balance adjustment, role change with last-owner guard, import duplicate policy, withdraw leave, support-session/suspend, etc.).
- **Static boards** for the rest, using fixed sample data for "Meridian Textiles" (248 employees, 3 active branches + 1 inactive).
- **Responsive coverage:** desktop 1440 for all admin screens; tablet 768 for dashboard, directory and onboarding; phone 390 for all employee self-service, onboarding branch form/checklist/multi-branch, admin nav drawer, directory cards and permission sections.

## 4. Design system (from `Main.dc.html`, `Components2.dc.html`)

| Token | Value |
|---|---|
| Primary | `#2B4ACB` (hover `#213CA8`, busy `#4A63D6`, soft `#EEF1FD`) |
| Success / Warning / Danger | `#0B7A62` / `#9A5B00` / `#B42318` (soft fills `#E6F5F0`, `#FFF3DB`, `#FDECEA`) |
| Canvas / surface / border / border-strong | `#F5F6F8` / `#FFFFFF` / `#E2E5EA` / `#CDD2DA` |
| Text primary / secondary / muted | `#0E1A2B` / `#475467` / `#667085` |
| Fonts | IBM Plex Sans (text), IBM Plex Mono (numbers, IDs, times) |
| Type scale | page title 24/32, section 16/24, card 15/22, body 14/22, label 13/18, table 14/20, helper 12/18, metric 30/36 |
| Spacing | 4 · 8 · 12 · 16 · 24 · 32 · 40 |
| Radius | 6 · 8 · 12; shadow-lg for menus and dialogs |
| Layout | sidebar 248 px / rail 72 px; header 64 px; content max 1360 px; card padding 20–24; field gap 16/24; table row 52 (44 dense); dialog 440 / 640 / full |
| Buttons | heights 32 / 40 / 48 (48 = mobile primary, full width); one primary per view; variants primary, secondary, ghost, destructive, disabled, busy ("Saving…") |
| Breakpoints | small mobile 320–374 (1 col, bottom nav) · mobile 375–479 (KPIs 2-up, tables → cards) · large mobile 480–767 (filters in drawer) · tablet 768–1023 (icon rail, 2-col forms) · laptop 1024–1439 (full sidebar) · desktop 1440+ (content capped 1360) |
| Components | KPI card, skeleton (shown after 300 ms, no shimmer for reduced motion), empty state, error/retry, status badge (text + colour, never colour alone), tabs, breadcrumbs, date-range picker with presets, multi-select chips (+N collapse), side drawer (440 px; full width < 600 px; focus trapped; Esc closes), toast (bottom), progress ring |
| Accessibility | WCAG 2.2 AA contrast, visible focus ring (2 px primary, 2 px offset), 44 px touch targets, labelled icon buttons, inline errors + top error summary, nothing typed is lost |

## 5. Discrepancies found

Inside the reference (canvas vs guide vs itself):

| # | Discrepancy | Evidence | Proposed resolution |
|---|---|---|---|
| D1 | Admin sidebar differs between boards: some show 11 items (Overview, Organization, Branches, Employees, Attendance, Leave Management, Holidays & Calendar, Roles & Permissions, Reports & Analytics, Settings, Audit Log); HR-admin boards show 8–9 (no Organization/Branches/Roles; some add Notifications). | `nav` arrays in OrgProfile/UserRoles vs LeaveTypes/Reports/MobileNav | Treat the menu as **permission-driven**: owner sees 11 + Notifications; HR admin sees what their role grants. One shell, items filtered by permissions. (Q-04) |
| D2 | Onboarding prototype uses a lighter sidebar (Overview, Employees, Attendance, Leave, Settings + per-branch progress list) than the main admin shell. | `OrgOnboarding.dc.html` shell vs `Dashboard.dc.html` | One shell. Show the "Branches" progress list in the sidebar **while any branch is under 100 %**. (Q-05) |
| D3 | Two different branch forms: onboarding form (name, address, city, state, PIN, optional contact, weekly per-day hours) and full form `BranchForm` (adds code, time zone, holiday calendar, weekly off, shift + extra shift, effective date, managers, status). "Create branch" in the directory links to the onboarding form; "Edit" links to the full form. | `Branches.dc.html` links | Keep both exactly as linked: create = short form, edit = full form. |
| D4 | Guide says the sidebar becomes a drawer "below 860 px"; design-system board says drawer < 768, rail 768–1023. | Guide p. 5 vs `Main.dc.html` breakpoints, `TabletDashboard` (768, rail) | Use the design-system board: < 768 drawer, 768–1023 rail, ≥ 1024 full sidebar. |
| D5 | Spelling: onboarding boards say "organisation", the rest say "organization". | Copy | Keep each screen's copy exactly as designed unless you choose one spelling. (Q-17) |
| D6 | Sample leave defaults differ: onboarding defaults Casual 12 / Sick 8 / Earned 15; other screens show Casual 8 / Sick 7 / Earned 1.25 per month. | `OrgOnboarding` `D.leave()` vs `LeaveTypes`, `MyLeave` | Sample data only; production values come from saved policy. No action. |
| D7 | Employee "Attendance" and "Holidays" tabs in the phone bottom bar link to `#` on some boards. | `EmpHome` tabs | Wire them to My attendance / My holidays (the intended targets from other boards). |
| D8 | Sign-in success goes straight to the owner dashboard; the Organization selection screen is not linked from the sign-in path. | `SignInTwoStep` → `Dashboard` | Route after sign-in by membership count and role (PRD §4.3): >1 org → selector; else role home. |

Design vs PRD (requirements the design does not cover, or covers differently) are listed in `requirements_traceability.md` §3 and turned into decisions in `open_questions.md`. The most consequential:

- **No time-zone capture in onboarding v2.** PRD requires an IANA time zone on the organization and each branch. Onboarding asks only for state; time zone appears only in the full branch edit form and the org profile. (Q-07)
- **No backend exists** and none is specified. (Q-01)
- **Employee screens are designed only at 390 px.** No desktop/tablet layout for self-service. (Q-03)
- **Several actions open screens that are not designed** (employee correction request form, "Ask the owner for access", 2-step setup, change password, team calendar, corrections list, platform billing/audit pages, etc.). (Q-12)

## 6. Constraints to carry into implementation

- Selecting "Set up an organization" / "Employee sign in" on Welcome must not grant a role (PRD §3). Access comes from the authenticated membership.
- Never show a successful punch, decision or save before the server confirms (PRD §8.1; mirrored by every busy state in the design).
- The design's percentages, KPIs and tables are fixed samples. Production builds must derive them from data (guide p. 122).
- Onboarding progress is kept in browser storage in the prototype. Production must persist it server-side per branch.
- Payroll, rotas, biometrics, GPS are out of scope (guide p. 122, PRD §2.4).

## 7. Recommended implementation sequence

Follows the master prompt's phases; the order inside each phase follows the user journey so every phase ends with a demonstrable flow.

| Phase | Screens | Demonstrable at the end |
|---|---|---|
| 1 Foundation | S01, S02, S96 components; responsive shell skeleton (sidebar / rail / drawer); router with guards; repository interfaces + demo data source (Q-01, Q-18) | Design-system gallery and an empty shell that resizes correctly from 320 to 1920 px |
| 2 Auth & shell | S03–S10, S72, S94 account parts; role-aware navigation (Q-04, Q-05) | Register → verify → sign in (2-step) → role home; forgot/reset; invite; org select; denied page |
| 3 Onboarding & org | S11–S29, S35–S38 | Create org → owner → first branch → configure to 100 %, resume, multi-branch, branch edit/deactivate |
| 4 Dashboards & employees | S30–S34, S39–S51 | Dashboards from data; directory, add/edit, profile, custom fields, full import wizard |
| 5 Attendance | S52–S56, S86–S88 | Punch in/out (server-confirmed), overview, records, missing-punch queue, correction, monthly grid |
| 6 Leave & holidays | S57–S66, S89–S93 | Apply → approve/reject → balance ledger; types, policy, balances, history; holiday calendar/list/form/import; schedule assignment |
| 7 Roles, settings, reports, notifications, audit | S67–S71, S73–S85, S95, (S97–S98 if Q-13) | Permission matrix and assignment; all settings pages; reports and exports; notification centres; audit log |
| 8 QA & release | All | Responsive matrix, end-to-end journeys, builds |

## 8. Re-fetching the reference

The canvas can be re-read at any time with the Artifact tool (`action: read`, `paths: ["project/<Board>.dc.html"]`). Board file names are listed in `screen_inventory.md`.
