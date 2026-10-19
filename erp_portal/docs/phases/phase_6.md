# Phase 6 — Leave, approvals and holidays

Status: **Complete, awaiting approval** · 19 Oct 2026

## Delivered

| Screen | Route | Notes |
|---|---|---|
| S90 My leave | `/my/leave` | Balance bars (used / pending / available) per type, next approved leave, recent requests, History and Apply |
| S89 Apply for leave | `/my/leave/apply` (`?type=&from=&to=`, `?amend=`) | Type with live balance, dates, full / first half / second half, day-by-day breakdown (holidays and weekly offs not counted), balance after approval, overlap / notice / backdate / blackout / balance messages, who it goes to; "Change dates" mode |
| S91 Leave request | `/my/leave/:id` | Status, details, progress timeline, Change dates, Withdraw (confirm sheet), Cancel approved leave before it starts, "changes requested" note |
| S92 Leave history | `/my/leave/history` | Type / year / status filters, "how N days is worked out", ledger with running balance |
| S93 My holidays | `/my/holidays` | Month calendar (holiday, optional, own approved leave, weekly off, today), month list, "Request" for optional holidays |
| S34 Team approvals | `/team/approvals` | Requests needing a decision (balance after, team off, reason), Approve / Reject… with reason, recently decided, own-request note |
| S57 Leave approvals | `/leave` (`?request=`) | Pending / Decided / All, search, sort, list + detail panel (phone: list or detail), balance impact, team on those dates, excluded days, Approve / Request changes / Reject…, own request routed to HR, history |
| S61 Requests | `/leave/requests` | Search, type / branch / period filters, status chips with counts (incl. Amended), table with decision text, export |
| S60 Balances | `/leave/balances` | Per-type available days (negative in red), pending count, Adjust side form (signed change, effective date, reason, preview, logged id), export |
| S58 Leave types | `/leave/types` | Type list, editor (basics, allowance & accrual, carry forward, request rules, counting rules, eligibility), unsaved-changes guard, worked example, new type |
| S59 Policy | `/leave/policy` | Approval routes (add / edit / remove), request rules, blackout periods (add / edit / remove), balance treatment toggles, "Fix N errors to save" |
| S62 Holiday calendar | `/holidays` | Month / Year / List, branch filter, legend, holidays in the month with Edit / View |
| S63 Holiday list | `/holidays/list` | Search, year, scope, status (past / in N days / on a weekly off), export; branch-setup holidays shown with a link to the branch |
| S64 Holiday form | `/holidays/new`, `/holidays/:id/edit` | Single day or range, category, description, whole organization or selected branches, optional, clash warning, "What this changes" (people, approved leave returned, people scheduled), delete; past holidays view-only |
| S65 Import / export | `/holidays/import` | .xlsx/.csv check (ready / duplicate / invalid with reasons) before anything is saved, export by year and scope as XLSX or CSV, blank template |
| S66 Schedules | `/holidays/schedules` | Precedence, assignments with people counts, new dated assignment with a preview of who moves and who keeps a more specific schedule |

Also updated from earlier phases:
- **Attendance:** "On leave" status (LV) and counts; organization holidays.
- **Employee home:** real balances and the open request.
- **Admin dashboard:** pending leave KPI (with "waiting over 48h"), approvals panel, leave taken by type, on leave today.
- **Branch dashboard:** on leave, leave requests waiting, who's off this week, on leave per department.
- **Branch detail:** present, on leave and missing punches today.
- **Employee profile:** "Leave & balances" with Adjust balance…, leave taken this month.

## The approval flow (gate demonstration)
1. **Isha (employee) applies.** She opens Leave › Apply for leave, picks Casual and 27–28 Oct, and sees "You'll use 2 days", her balance after approval, and that it goes to Aarav Bhatt. She submits.
2. **The request is pending.** Its page shows "Waiting for Aarav Bhatt" and the 2 days are held from her balance.
3. **Aarav (leave approver) decides.** His Approvals page shows the request with the balance after and the team off those days. He taps Approve, or Reject… with a required reason.
4. **Isha sees the result.** The request is approved, the leave shows as her next approved leave, and the days move from pending to used.
5. **Approvers can't decide their own leave.** Jignesh's own earned leave is routed to HR and shows "Routed to HR" with no actions for him. Hetal (HR) approves it.

This whole flow is covered end to end by the widget test "Isha applies, Aarav approves, the balance drops"; the rejection, request-changes, withdraw, change-dates and cancel paths have their own tests.

## Rules implemented
- **Balances** are computed from records, never stored (D-42). Upfront allowances are prorated for joiners; monthly accrual starts after the waiting months; pending days are held.
- **Day counting** follows the work calendar (D-43). Half days count 0.5, and holidays added later return days.
- **Validation:**
  - type eligibility and branch availability
  - date order
  - half day only for a single date, and only on types that allow it
  - nothing left to count
  - the longest request
  - backdating (sick only, up to the policy limit)
  - notice
  - blackouts
  - overlap, with the next day that counts suggested
  - balance, with an optional negative allowance
  - the optional-holiday limit
- **Routing and decisions** (D-44, D-45): no self-approval anywhere, rejection reasons required, and the request flow submit → request changes / approve / reject → amend / withdraw / cancel (D-46).
- **Holidays:** organization calendar plus branch lists; past days locked (D-47); optional holidays (D-48).
- **Schedules:** dated precedence (D-49).
- **Attendance:** approved leave shows as "On leave" (D-50).

## Deviations from the design
- **Branch managers decide requests across their branch** (board S57). The design's "If approver is away" column has no backing data, so it isn't shown.
- **Notifications** ("you'll get a notification", "employees are notified") are described in copy but not sent. Notifications arrive in Phase 7.
- **Leave year and rounding** (S59) are fixed: January–December, shown to 0.5 days. Encashment and "carried days expire" (S58) aren't offered, because nothing uses them yet.
- **Attachments** for sick leave (S58 "Attachment") aren't collected.
- **Team calendar** (S34 menu) stays hidden, as in Phase 5 (Q-12).
- **Holiday import** reads the first sheet with a header row (Date, Holiday, Applies to, Category). Rows can't be edited in place; you fix the file and choose it again.

## Verification (19 Oct 2026)

| Check | Result |
|---|---|
| Format check | 0 files changed |
| `flutter analyze` | No issues |
| `flutter test` | 520 passed, 0 failed (102 new) |
| Line coverage | 90.9% overall (17372 / 19105); leave and holiday code 90.4% |
| `flutter build web --release` | Built |
| Responsive | Every new page for owner, branch manager, leave approver and employee at 320 / 390 / 768 / 1024 / 1440 px and 200% text |
| Screenshots | 89 images (26 new) |

Bugs found and fixed:
- **Riverpod circular dependency.** Submitting, approving or rejecting leave threw a circular-dependency error: the leave notifier read the provider that depends on it. The leave widget tests caught it.
- **Double HR step.** A long request from someone whose manager is the HR admin was routed to HR twice.
- **Branch-scope leak.** A leave approver opening Balances by URL saw every branch. It is now limited to their reports.
- **Demo data.** Some seeded requests fell on Sundays or holidays (0 days). Some approved leave days also had attendance punches.
- **Overlap suggestion.** The overlap message suggested a start date that was a holiday.
- **Layout:**
  - Choice chips stretched to full width.
  - The balance bar was invisible (zero height).
  - Overflows: legend labels at 320 px, and the approver card header at 200% text.

## Known limitations
- Demo repository; everything resets on reload (D-01). A backend must apply the same validation, routing and self-approval rules (`LeaveRepository` says so).
- Year-end carry-forward and lapse are shown, not run as a job; carry is seeded as a 1 Jan adjustment.
- Schedule assignments can be added, not edited or removed.
