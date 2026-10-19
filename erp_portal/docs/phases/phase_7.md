# Phase 7 — Roles, settings, reports, notifications and audit

Status: **Complete, awaiting approval** · 20 Oct 2026

## Delivered

| Screen | Route | Notes |
|---|---|---|
| S67 Roles | `/roles` | System (locked) and custom roles, scope, people count (→ S70), status, View/Edit, Duplicate, Create role |
| S68 Role editor | `/roles/:id`, `/roles/new?from=` | Name, description, "works like", active, data scope, permission matrix with owner-only locks and not-applicable cells, changed cells highlighted, pending changes, assigned people, Review & save → reason → "Confirm it's you" |
| S69 Role editor (phone) | same, < 720 px | One section per module with switches, "n of m allowed", "Edited" |
| S70 People & access | `/roles/people?role=` | Search, role filter, membership, Change role dialog with branches, last-owner block, high-impact confirmation |
| S71 Invitations | `/roles/invitations` | Waiting / expired / not delivered / accepted, Resend all expired, Resend, Edit email and resend, Revoke |
| S76 Notifications | `/notifications` | Category chips, unread dots, detail panel with facts and action, Mark all read, link to settings |
| S95 My notifications | `/my/notifications` | All / Unread, Today / Earlier, opens the linked page and marks read |
| — Bell | top bar | Unread count; leads to S76 or S95 |
| S77 Audit log | `/audit-log` | Filters (period, actor, action, entity, branch, search), side detail, masked values, paging, export (logged) |
| S78 Audit event | `/audit-log/:id` | What changed, people affected, related events, context, sealed-entry check with chain verification, owner "Reveal" with reason |
| S80 Settings | `/settings` | Area cards with live summaries, attention banner, search with no-match state |
| S79 Attendance policy | `/settings/attendance` | Per branch: grace, half day if late by, early departure; change history from the audit log |
| S81 Work schedules | `/settings/schedules` | Shift templates attendance uses, expected hours, breaks, overnight rule, usage; edit hours / assign links |
| S82 Notification settings | `/settings/notifications` | Event × recipient × channel matrix (locked and n/a cells), daily digest, email preview |
| S83 Security | `/settings/security` | Two-step policy, password and session rules, invitation and reset link lifetimes; password confirmation |
| S84 Data & export | `/settings/data` | Export rights by role and area, file formats, retention, audit access (from Roles) |
| S85 Branding & localization | `/settings/branding` | Brand color with contrast warning, language and formats, live preview |
| S73 Report center | `/reports` | Nine reports in four groups, locked ones say why, configure panel (dates, branch, department, columns with restricted ones), preview count, XLSX/CSV, View results, Export, recent exports |
| S74 Report results | `/reports/results?report=…` | Filter chips, totals, caveat note, sortable columns, 10/50 rows paging, Export CSV/XLSX |
| S75 Export history | `/reports/exports` | Anyone you can see / only me, report, period; Ready / Failed / Expired; logged downloads |
| S94 My profile | `/my/profile` | Own contact edit (mobile, emergency contact, language), employment (read-only), reset password by email, two-step status, sign out |

Also updated from earlier phases:
- Every create, update or decision now writes an audit entry and, where the preferences say so, a notification. This covers employees, imports, invitations, attendance corrections, leave requests and decisions, leave types, policy and adjustments, holidays, schedules, the organization, branches, roles and settings.
- Leave approval actions are hidden when the role no longer has leave approval.

## The approval gate: roles, reports and settings
1. **The owner changes a role.** Ankit opens Roles › Branch Manager, unticks *Leave · Approve*, and reviews (pending changes, who it affects). He adds a reason and confirms with his password. The change is saved and the audit log shows `auth.reauth` and `role.update` with before and after.
2. **The change reaches the member.** Jignesh (Branch Manager) opens Leave approvals and no longer has Approve buttons. Removing *Holidays · View* sends him to "Access denied".
3. **The owner changes a person's role.** On People & access, Ankit can't downgrade himself (only owner). Changing Aarav to Employee updates his session and employee record.
4. **HR runs a report.** Hetal opens Reports › Monthly attendance summary and exports a CSV. It appears in Export history; the export and each download are logged.
5. **A branch manager's reports stay in scope.** Jignesh's reports only contain Surat, never personal email, and the audit report is refused. When the owner turns off his attendance export right, Export disappears with the reason.
6. **Security settings take effect.** The owner requires two-step for everyone and confirms with his password. Isha's next sign-in asks for a code.

Each step is covered by a widget test in `test/widget/features/phase7_screens_test.dart`.

## Deviations from the design
- **Platform administration (S97–S98)** is not built. The brief makes it optional and it wasn't approved (D-62).
- **Work schedules (S81)** are shown, not edited as free templates. Times come from branch hours plus the fixed night shift, because the attendance engine computes from those (D-61).
- **Branding (S85)** is saved and previewed. The app keeps its theme and English. There is no logo upload here; it links to the Organization page.
- **Attendance policy (S79)** edits the branch rules the engine uses. The design's named shared policies, repeated-lateness alerts, rounding, overtime flag and "takes effect on" date aren't modelled. New rules apply to the whole month.
- **Emails** are queued in an outbox, never sent. The daily digest is a stored setting only.
- **My profile:** two-step setup and signed-in devices were never designed (⚠ on the board), so they're shown as status only.
- **Failed sign-in attempts** are seeded in the audit log, but not recorded live: there's no organization before sign-in.

## Verification (20 Oct 2026)

| Check | Result |
|---|---|
| Format check | 0 files changed |
| `flutter analyze` | No issues |
| `flutter test` | 584 passed, 0 failed (64 new) |
| Line coverage | 90.9% overall (21437 / 23596); Phase 7 code 90.2% |
| `flutter build web --release` | Built |
| Responsive | All Phase 7 pages (owner, branch manager, employee) at 320 / 390 / 768 / 1024 / 1440 px and 200% text, including the permission matrix and report tables |
| Screenshots | 110 images (21 new) |

Bugs found and fixed:
- **Circular dependencies.** Four places read a provider that depends back on the reader, including the role editor's save. They were broken by moving access actions into a separate service and by building data from the notifier's own state.
- **Wrong owner in other organizations.** The demo owner was seeded as owner of every organization, which upgraded him in Patel Dyes, where he is HR Admin. A routing test caught it.
- **Notification linked to a forbidden page.** HR's "Invitation not delivered" notification opened a page HR couldn't reach, so Invitations now follows the right to invite people.
- **Approve buttons stayed visible** after leave approval was removed from a role.
- **Audit order with tied timestamps.** Entries with the same timestamp could show in the wrong order; they now keep their recorded order.
- **Layout:**
  - Overflows on the employee notifications header and the profile password row at 200% text.
  - Checkbox tiles inside cards hid their ink effects, which Flutter reports as an error.
  - The matrix legend used glyphs the font can't draw.

## Known limitations
- **Demo data:** everything is in demo repositories and resets on reload (D-01). Authorization here only decides what to show; a backend must enforce every permission, scope and export rule, keep the audit log append-only, and invalidate sessions on role changes (D-53).
- **Settings not enforced:** password minimum length, lockout and idle timeouts are stored but not enforced by the demo sign-in.
