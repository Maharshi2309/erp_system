# Phase 4 — Dashboards and employee management

Status: **Complete, awaiting approval** · 18 Oct 2026

## Delivered

| Screen | Route | Notes |
|---|---|---|
| S30–S32 Owner / HR dashboard | `/overview` | Branch and period filters, refresh, branch setup strip (owner), 7 KPIs, headcount by branch, needs attention, setup checklist, upcoming holidays; 3-up KPIs on tablet, 2-up on phone |
| S33 Branch manager dashboard | `/branch-dashboard` | Locked "Branch: Surat", today by department (people and scheduled), off this week, scope footnote |
| S39–S41 Directory | `/employees` | Search (name, ID, email, mobile), branch/department/status/type filters, sort, pagination 10/25/50, column chooser, bulk resend invite / change branch / deactivate, row actions, template, import, export; tablet: 3 columns + filter panel + chips; phone: cards + "Load 25 more" |
| S42 Profile | `/employees/:id` | Eight tabs; masked contact details with "Show" for owner/HR; attendance calendar with branch holidays and weekly offs; leave allowances from the branch policy; account and access; custom fields; activity |
| Lifecycle | profile, directory, edit | Deactivate (reason), reactivate, start notice period (last day), terminate and archive (effective date + reason), reset password link, resend invitation |
| S43 Add employee | `/employees/new` | Nine sections with index and error dots, error summary with jump links, suggested ID, branch shifts, manager at the branch, custom fields by department, role, Save & send invite / Save without inviting |
| S44 Edit employee | `/employees/:id/edit` | Changed fields marked with the old value, "Your changes" panel, read-only ID / joining date / mobile rules, branch move consequences + effective date, review dialog, danger zone |
| S45 Field builder | `/settings/employee-fields` | Reorder, new field, key from label, type lock, options with usage counts (rename yes, remove in-use no), required with impact count, who-can-see matrix, sensitive, applies to, live preview, archive / restore |
| S46–S51 Import | `/employees/import`, `/employees/import/results/:id` | Upload with file checks, template, recent imports; auto-matching, required checklist, date-format question; validation counters and filters, error report; duplicate policy with acknowledgement; confirm with invitation toggle; results with downloadable report |

## Deviations from the design
- Attendance and leave figures on dashboards and profiles show "—" or an empty state until Phases 5–6 (D-24); no invented numbers.
- The design's sample numbers that depend on attendance (present 196, absent 17 …) are therefore not shown; upcoming holidays count 4 (next 30 days from branch calendars) instead of the drawn 2.
- Drag-and-drop on the upload zone is not supported; the "Choose file" button is.
- The design's "Preview: what a rejected file looks like" demo button is replaced by the real rejection state.
- A branch move applies immediately; the effective date is recorded in the history (D-33).
- Deepa Nair and Gauri Pandya report to Jignesh Parmar in the seed, because the rule "manager must work at the same branch" would otherwise reject the design's cross-branch managers.

## Verification (18 Oct 2026)

| Check | Result |
|---|---|
| Format check | 0 files changed |
| `flutter analyze` | No issues |
| `flutter test` | 371 passed, 0 failed (98 new) |
| Line coverage | 90.6% overall (10048 / 11094); Phase 4 code 90.6% |
| `flutter build web --release` | Built |
| Responsive | Every Phase 4 page, profile tab and the field editor at 320 / 390 / 768 / 1024 / 1440 px; at 200% text on 390 px |
| Screenshots | 52 images in `test_screenshots/output/` (19 new) |

Bugs found and fixed while testing:
- Page and card headers overflowed when actions didn't fit (800 px tablet); actions now wrap and stack.
- Attendance calendar cells overflowed at 320 px.
- Checkbox rows inside cards tripped Flutter's ink assertion; replaced with the app's labelled checkbox.
- Seed data: generated names repeated; branch counts left out inactive people.

## Known limitations
- Demo repository only; everything resets on reload (D-01).
- Invitations and reset links are recorded, not emailed (Phase 7 notifications).
- The organisation-wide audit log is Phase 7; each employee keeps their own activity history now.
- Departments are a fixed list until Settings (Phase 7).
