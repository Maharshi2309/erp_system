# Phase 5 — Attendance management

Status: **Complete, awaiting approval** · 19 Oct 2026

## Delivered

| Screen | Route | Notes |
|---|---|---|
| S86 Employee home | `/home` | Status chip, live session timer, today's total and progress, Punch in / Punch out (busy state, nothing changes until the server confirms, failure message), correction notice, leave allowances, recent days, upcoming holidays |
| S87 My attendance | `/my/attendance` | Month select (3 months), KPIs, day list with times, notes (in progress, corrected by, late, requested) and status |
| S88 Day detail | `/my/attendance/:date` | Worked / expected / break / shift, timeline with sources and corrections, exceptions, **Request correction** form (Q-12 b) within 3 days |
| S52 Overview | `/attendance` | Daily / Weekly / Monthly, branch and department filters, KPIs, arrivals histogram or per-day chart, branch table, missing-punch list, working right now |
| S53 Records | `/attendance/records?date=&branch=` | Day navigation, KPIs, search, filters (exceptions only, late, missing), table, detail panel with timeline and "Correct attendance…", weekly/monthly totals, export |
| S54 Missing punches | `/attendance/missing-punches` | Overdue / recent groups, state (no response, reminded, correction requested, waiting for approval), remind, remind all, reject request, correct / review request; "all clear" state |
| S55 Correct attendance | `/attendance/correct/:employee/:date` | Punches table with missing and movable times, live worked/status preview, reason, second-approval routing, employee's request, history |
| Corrections (Q-12 b) | `/attendance/corrections` | Waiting for approval (approve / reject), employee requests, recent decisions |
| S56 Monthly summary | `/attendance/monthly` | Team grid with legend and totals, day list per person with Correct, branch/department filters, export |
| Exports (Q-12 b) | `/attendance/exports` | Date range, branch, exceptions only → .xlsx |

Also updated from Phase 4: the owner/HR dashboard, branch manager dashboard and employee profile now show real attendance (present, absent, late, working now, trend, today so far, scheduled vs worked, missing punches, department coverage, month at a glance, attendance calendar).

## Rules implemented
- Punches stored as UTC; work days and shifts in the branch time zone (D-34).
- Night shifts stay on their start date (D-35); unpaid breaks; statuses per D-36.
- No duplicate active sessions; safe retries via request id (D-38).
- Originals kept; corrections pending until approved; manager corrections need a second approver; no self-approval (D-37).
- Branch scope: branch and attendance managers see only their branches.

## Deviations from the design
- "On leave" figures are 0 until leave exists (Phase 6).
- Payroll export blocking for overdue days is described, not enforced (payroll is out of scope).
- Reminders are recorded; the notification itself arrives with Phase 7.
- A "Custom range…" option on My attendance is not offered (three months instead).
- Break start/end buttons are not on the employee home (not in the design); breaks come from session gaps and kiosk break events.

## Verification (19 Oct 2026)

| Check | Result |
|---|---|
| Format check | 0 files changed |
| `flutter analyze` | No issues |
| `flutter test` | 418 passed, 0 failed (47 new) |
| Line coverage | 91.0% overall (12825 / 14089); attendance code 92.6% |
| `flutter build web --release` | Built |
| Responsive | All attendance pages (admin and employee) at 320 / 390 / 768 / 1024 / 1440 px and 200% text |
| Screenshots | 63 images (11 new) |

Bugs found and fixed:
- Night-shift punches after midnight were counted on the next day.
- Demo accounts for Hetal, Jignesh and Mitesh weren't linked to their employee records, so the second-approval rule didn't apply.
- Overflows: Daily/Weekly/Monthly toggle at 320 px, correction time field, recent-attendance row and day list at 200% text, chart bars 1 px too tall.
- Edge-to-edge cards had unpadded headers.

## Known limitations
- Demo repository; everything resets on reload (D-01). Real punches need a server clock and location/kiosk checks.
- Time zone data covers 10 years.
