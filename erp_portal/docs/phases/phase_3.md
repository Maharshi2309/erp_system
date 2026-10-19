# Phase 3 — Organization onboarding and branch setup

Status: **Complete, awaiting approval** · 16 Oct 2026

## Delivered

| Screen | Route | Notes |
|---|---|---|
| S12 Onboarding start | `/onboarding` | Set up an organisation, or join with an invitation; sign out |
| S13–S14 Create organisation | `/onboarding/create` | Logo, name, team size; error summary; makes the creator the owner and opens the new organisation |
| S15–S17, S23–S25 Setup home | `/overview` (owner) | 3-step checklist, branch cards with progress rings, "Welcome back" banner that resumes the last step, quick actions |
| S16 Owner profile | `/organization/owner-profile` | Photo, name, mobile, designation; email is read-only |
| S18–S19 Branch details & hours | `/branches/new`, `/branches/:id/basics` | Address, PIN, optional contacts; weekly hours with quick fills and "Copy to…"; per-day errors |
| S20–S22 Branch setup | `/branches/:id/setup?step=` | Progress ring, checklist with weights, side panel per step, kept drafts, "Copy from another branch", final review, completed state |
| S35 Organisation profile | `/organization` | View and edit; legal-name and time-zone changes need confirmation |
| S36 Branches | `/branches` | Search, status filter, sort, setup %, empty and no-results states |
| S37 Edit branch | `/branches/:id/edit` | Details, hours, time zone (inherit or own), status; a branch with employees can't be made inactive |
| S38 Branch detail | `/branches/:id` | Header actions, setup banner, six tabs (Employees and Activity wait for Phases 4 and 7) |
| Owner sidebar | — | BRANCHES group with % and "Add branch" while setup is unfinished |

Setup panels: attendance rules, holiday calendar (Gujarat / national / none, custom holidays), leave policies, roles & permissions (owner manages or invite a manager), reminders (optional), final review.

Demo data: Meridian Textiles: Ahmedabad HQ 100%, Surat 65% (bookmarked at holidays), Vadodara 40%, Rajkot depot inactive. Brand-new registrations start with no organisation.

## Deviations from the design
- Logos and photos: PNG/JPG only, no SVG (D-17).
- Panel drafts are kept for the session only (D-18).
- "Open full dashboard" on the completed setup home is hidden until the dashboard exists (Phase 4).
- Branch detail shows only real data: employee count and details. Present-today, leave and missing-punch figures arrive with Phases 5–6.
- The kiosk option is saved as a setting; the kiosk itself is not built.
- On phones, each day's "Copy to…" button is an icon button to fit the row.

## Verification (16 Oct 2026)

| Check | Result |
|---|---|
| Format check | 0 files changed |
| `flutter analyze` | No issues |
| `flutter test` | 273 passed, 0 failed (58 new) |
| Line coverage | 90.6% overall (5410 / 5973); Phase 3 code 86.7% |
| `flutter build web --release` | Built |
| Responsive | Every Phase 3 page and setup panel at 320 / 390 / 768 / 1024 / 1440 px, and at 200% text on 390 px |
| Screenshots | 33 images in `test_screenshots/output/` (17 new) |

Bugs found by the tests and fixed:
- A new branch could get the same name as an existing one when its placeholder ID matched (the uniqueness check skipped it).
- Opening a second `?step=` link while the setup page was already showing did nothing.
- Layout overflows at 320 px or 200% text: focus-page header, hours rows, setup-home card buttons, progress ring label, onboarding step chips, logo text.
- Branches table was wider than a 1440 px screen; addresses now wrap in a fixed-width column.
- A damaged image file crashed its preview; it now shows a broken-image mark.

## Known limitations
- Demo repository only; everything except "Keep me signed in" resets on reload (D-01).
- The manager invitation is recorded on the branch but no email is sent and no account is created (Phase 4/7).
- Toasts sit over the sticky action bar on phones for their 4 s.
- HR admins can't see Organization or Branches (role matrix S68 vs board S36; open question).
