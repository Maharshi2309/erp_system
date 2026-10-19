# Requirements Traceability

Maps every PRD v1.0 requirement to the screens that cover it, the implementation phase and the planned test. Phase numbers are the master prompt's (1 Foundation · 2 Auth & shell · 3 Onboarding & org · 4 Dashboards & employees · 5 Attendance · 6 Leave & holidays · 7 Roles, settings, reports, notifications, audit · 8 QA & release).

Coverage: **Covered** = a designed screen implements it · **Partial** = designed screen exists but misses part of the rule · **Gap** = no designed screen · **Backend** = enforced server-side; the client only reflects it.

Test types: U = unit (domain/provider) · W = widget · I = integration (journey) · B = backend/authorization test (needs a backend, Q-01).

## 1. Authentication and access (PRD §3, §4.2–4.3, §16)

| ID | Requirement (PRD) | Screens | Cover | Ph | Planned test |
|---|---|---|---|---|---|
| R-AUTH-01 | Welcome offers owner setup vs employee sign-in; the choice is not a security mechanism (§3, §4.1) | S03 | Covered | 2 | W: both cards route; U: no role assigned from card |
| R-AUTH-02 | Owner account: name, email/phone, password, verification, terms (§4.1) | S04, S05 | Covered | 2 | W: password rules live; terms required; U: validators |
| R-AUTH-03 | Sign-in with email or employee ID + password; generic failure message (§4.2) | S03 | Covered | 2 | W: generic error text; U: identifier parsing |
| R-AUTH-04 | Validate credentials, account status, membership, branch/role scope (§4.2) | — | Backend | 2 | B; U: repository maps failures |
| R-AUTH-05 | Multi-org users choose an organization or use last-used (§4.3) | S10 | Covered | 2 | W/I: >1 membership shows selector; deactivated membership shown, not selectable ⚠ Q-14 |
| R-AUTH-06 | Account recovery with expiring, single-use links (§16) | S07, S08 | Covered | 2 | W: sent state never reveals existence; expired-link state |
| R-AUTH-07 | MFA recommended/required for admins (§16) | S06, S83 | Covered | 2 / 7 | U: code formats, 3-try lockout state; W: backup-code mode |
| R-AUTH-08 | Invitation acceptance via expiring link, user sets own password (§6.3, §20) | S09, S71 | Covered | 2 | W: confirm-password mismatch; expired invite ⚠ not drawn |
| R-AUTH-09 | Sessions: expiry, logout, re-auth for high-risk changes (§16) | S96 (session expired), S83, S35 | Partial | 2 / 7 | I: expired session keeps form draft; W: confirm-it's-you dialog |
| R-AUTH-10 | Route to role home after sign-in (§4.2) | S30, S33, S34, S52, S86, S97 | Covered (D8) | 2 | U: router redirect per role; W: guard tests |
| R-AUTH-11 | Unauthorized pages show permission-denied with who to ask (guide) | S72 | Covered | 2 | W: guard renders S72 in caller's shell |

## 2. Onboarding, organization and branches (PRD §4.1, §5)

| ID | Requirement | Screens | Cover | Ph | Planned test |
|---|---|---|---|---|---|
| R-ORG-01 | Guided owner setup ending on dashboard with setup checklist (§4.1) | S11–S25 | Covered | 3 | I: noOrg → create → owner → branch → 100 % |
| R-ORG-02 | Organization fields: display name (req), legal name/ID, address, contact email, **default IANA time zone (req)**, logo, status (§5.1) | S13 (name, logo, size only), S35 | **Partial** — onboarding collects 3 fields; address, contact and time zone only in S35 | 3 | U: org validators; W: S35 sensitive-change confirm ⚠ Q-07 |
| R-ORG-03 | Logo upload with type/size validation (§5.1) | S13, S16, S85 | Covered | 3 | U: ≤ 2 MB, image types; W: error copy |
| R-ORG-04 | Branch: name (req), code (unique in org), address, contact, **time zone (req)**, schedule, weekly off, holiday calendar, managers, status (§5.2) | S18 (short), S37 (full) | **Partial** — short form has no code or time zone | 3 | U: duplicate name/code; PIN 6 digits; closing > opening; W: copy-to days |
| R-ORG-05 | Multiple branches, now or later; independent progress (§4.1) | S23, S36 | Covered | 3 | U: progress formula per branch (all weights, invalid-after-save drop) |
| R-ORG-06 | Initial policy defaults: work week, hours, grace, leave types, holiday calendar (§4.1) | S21 panels | Covered | 3 | U: defaults; W: panel save/keep draft/copy-from |
| R-ORG-07 | Invite first admin/HR and import employees, or skip (§4.1) | S21 roles panel (branch manager invite); S30 checklist "Invite an HR admin"; quick action Manage employees | Partial | 3 / 4 | I: skip path reaches dashboard |
| R-ORG-08 | Deactivate instead of delete; history kept (§5.2–5.3) | S36, S37, S38 | Covered | 3 | W: inactive branch visible; deactivation blocked while employees assigned |
| R-ORG-09 | Time-zone change applies forward; history keeps original context (§5.3) | S37 ("Effective from") | Partial | 3 / 5 | U: calculations use record-time zone |
| R-ORG-10 | Draft kept when panels close; "continue where you left off" (guide) | S21, S24 | Covered | 3 | U: draft store; W: banner resume target |

## 3. Employees and custom fields (PRD §6)

| ID | Requirement | Screens | Cover | Ph | Planned test |
|---|---|---|---|---|---|
| R-EMP-01 | Directory: search, filter, sort, paginate, bulk actions with confirmation (§6, §15) | S39–S41 | Covered | 4 | W: search/filter/sort/paginate; bulk deactivate confirm with count |
| R-EMP-02 | Standard fields by group (identity, contact, employment, placement, schedule, account) (§6.1) | S42, S43 | Covered | 4 | U: entity + validators; W: required markers |
| R-EMP-03 | Create validates required fields, duplicate IDs/emails, branch membership (§6.3) | S43 | Covered | 4 | W: error summary + jump links; U: duplicate email |
| R-EMP-04 | Edit tracks who/when; important changes audited; read-only after attendance exists (§6.3) | S44 | Covered | 4 | W: change summary; read-only fields locked |
| R-EMP-05 | Transfer branch with effective date and consequences (§6.3) | S44 | Covered | 4 | U: manager must belong to new branch |
| R-EMP-06 | Activate / deactivate / terminate-archive with reason (§6.3) | S42, S44 | **Partial** — deactivate only; terminate/archive not drawn | 4 | Q-12 |
| R-EMP-07 | Invite / reset via secure link; never plaintext passwords (§6.3) | S42 (Reset password link), S43 (Save & send invite), S71 | Covered | 4 / 7 | W: no password field in admin forms |
| R-EMP-08 | Custom fields: types, key, required, options, visibility/edit per role, applies-to, archive, type lock (§6.2) | S45 | Covered | 4 | U: type-change lock when values exist; option-in-use cannot be removed |
| R-EMP-09 | Required custom fields validated on manual entry, import and edit (§18) | S43, S47–S48, S44 | Covered | 4 | U: shared validator used by form and import |
| R-EMP-10 | Sensitive fields masked and permission-restricted (§6.1 privacy) | S42, S45, S84 | Covered | 4 | W: masked values render; B: API enforcement |

## 4. Import (PRD §7)

| ID | Requirement | Screens | Cover | Ph | Planned test |
|---|---|---|---|---|---|
| R-IMP-01 | Template with standard + active custom fields | S39, S46 | Covered | 4 | U: template columns |
| R-IMP-02 | Upload .xlsx/.csv; validate type, size (5 MB), rows (2,000), headers | S46 | Covered | 4 | U: file checks; W: rejected-file state |
| R-IMP-03 | Map columns; ignore or map to custom fields | S47 | Covered | 4 | U: auto-match by name |
| R-IMP-04 | Ambiguous dates: ask, don't guess | S47 | Covered | 4 | U: ambiguity detection DD/MM vs MM/DD |
| R-IMP-05 | Preview valid / warnings / duplicates / errors before commit | S48 | Covered | 4 | U: row classifier; counts add up |
| R-IMP-06 | Duplicate policy: reject by default; update needs permission + confirmation | S49 | Covered | 4 | W: acknowledgement gate |
| R-IMP-07 | Commit in controlled batch; summary created/updated/skipped/failed matches reality | S50, S51 | Covered | 4 | U: result counts reconcile; I: full wizard |
| R-IMP-08 | Downloadable error report without unrelated data | S48, S51 | Covered | 4 | U: report rows only include failed rows |
| R-IMP-09 | No shared default passwords; invitations instead | S50 | Covered | 4 | W: invite toggle copy |
| R-IMP-10 | Log importer, time, policy, result | S77 (`import.commit`) | Covered | 4 / 7 | B |

## 5. Attendance (PRD §8)

| ID | Requirement | Screens | Cover | Ph | Planned test |
|---|---|---|---|---|---|
| R-ATT-01 | Status: Not punched in / Working / On break / Day completed (§8.1) | S86 | Partial — no On break state or break button | 5 | U: state machine; Q-10 |
| R-ATT-02 | Punch in/out; one open session by default; duplicates rejected/idempotent (§8.1, §18) | S86 | Covered | 5 | U: idempotency key; double-tap ignored while pending |
| R-ATT-03 | Current session timer, day total, schedule, exceptions (§8.1) | S86, S88 | Covered | 5 | U: duration from paired events |
| R-ATT-04 | Never show success until server confirms; clear offline/failure feedback (§8.1) | S86, S96 | Covered (conflict with offline state, Q-09) | 5 | W: failure keeps previous status |
| R-ATT-05 | Admin daily/weekly/monthly views with in/out, worked, breaks, expected, ±, late, early, status (§8.2) | S52, S53, S56 | Covered | 5 | W: view toggle; U: status derivation |
| R-ATT-06 | Filters: branch, department, manager, employee, dates, status, missing, late (§8.2) | S52, S53, S54 | Covered (manager filter ⚠ not drawn) | 5 | W: filter chips |
| R-ATT-07 | Authorized correction with reason, original, corrected, actor, time, approval (§8.2) | S55 | Covered | 5 | U: reason ≥ 5 chars; out > last in; W: "Send for approval" flow |
| R-ATT-08 | Employee views own history and requests correction if enabled (§8.2) | S87, S88 | **Partial** — request form not drawn | 5 | Q-12 |
| R-ATT-09 | Status labels Present, Absent, Late, Half day, On leave, Holiday, Weekly off, Missing punch (§8.2) | S53, S56, S87 | Covered | 5 | U: label mapping |
| R-ATT-10 | UTC storage, IANA zones, DST-safe, paired-event math minus unpaid breaks (§8.3) | — | Backend + domain | 5 | U: overnight, DST, multi-session cases |
| R-ATT-11 | Schedule precedence employee > shift group > branch > org (§8.3) | S66 | Covered | 6 | U: resolver |
| R-ATT-12 | Grace period, overtime flag, overnight attribution, rounding display-only (§8.3) | S79, S81 | Covered | 5 / 7 | U: grace & attribution |
| R-ATT-13 | Missing punch flagged, never auto-closed silently (§8.3) | S54, S79 (policy choice) | Covered | 5 | U: open session remains incomplete |

## 6. Leave (PRD §9)

| ID | Requirement | Screens | Cover | Ph | Planned test |
|---|---|---|---|---|---|
| R-LV-01 | Leave types with paid/unpaid, balance tracking, accrual, allowance, carry-forward, expiry, min/max, attachment, eligibility (§9.1) | S58 | Covered | 6 | U: type validation |
| R-LV-02 | Full/half day; weekends & holidays counting (§9.1) | S58, S89 | Covered (hourly leave not designed — Q-11) | 6 | U: duration calculator across holidays/weekly offs |
| R-LV-03 | Approval routes, escalation/substitute (§9.1) | S59 | Covered | 6 | U: route resolution, self-approval skip |
| R-LV-04 | Initial balances manual/import with audit (§9.1) | S60 | Partial — manual adjust only | 6 | U: ledger entry on adjust |
| R-LV-05 | Request: type, dates/partial, reason, attachment; calculated impact (§9.2) | S89 | Covered (attachment not drawn) | 6 | W: balance-after live; overlap blocks submit |
| R-LV-06 | Drafts if enabled; edit/cancel while allowed; amendments re-approve (§9.2) | S91 | Covered (drafts not drawn) | 6 | W: withdraw confirm; change dates resubmits |
| R-LV-07 | Prevent overlaps and overdraw unless policy allows (§9.2) | S89, S59 | Covered | 6 | U: overlap; negative-balance policy |
| R-LV-08 | Status lifecycle Draft/Pending/Approved/Rejected/Cancelled-Withdrawn/Amended (§9.3) | S57, S61, S90, S91 | Covered | 6 | U: transition table |
| R-LV-09 | Balance shows opening, accrued, used, pending, adjustments, available; ledger (§9.3, §17) | S92, S42, S60 | Covered | 6 | U: ledger formula |
| R-LV-10 | Approve/reject with comment; staffing context; filters (§9.3) | S57, S34 | Covered | 6 | W: reject requires reason |
| R-LV-11 | No self-approval by default (§18) | S57 ("Routed to HR"), S34 footnote | Covered | 6 | U + B |
| R-LV-12 | Restrict sensitive reasons/attachments (§9.3) | — | Gap | 6 | Q-12 |

## 7. Holidays and calendars (PRD §10)

| ID | Requirement | Screens | Cover | Ph | Planned test |
|---|---|---|---|---|---|
| R-HOL-01 | Holiday: name, date/range, description, category, scope (org / branches), optional groups | S64 | Covered (employee groups not drawn) | 6 | W: duplicate-date warning |
| R-HOL-02 | Org-wide and branch-specific; optional/floating | S62–S64, S93 | Covered | 6 | U: branch holiday visible only to that branch |
| R-HOL-03 | Calendar and list by month/year; bulk import/export | S62, S63, S65 | Covered | 6 | U: import row validation |
| R-HOL-04 | Effect on attendance expectation and leave days; past not rewritten | S64 impact panel, S63 (past read-only) | Covered | 6 | U: past holiday immutable |
| R-HOL-05 | Weekly-off patterns per branch/employee | S37, S66 | Covered | 6 | U: weekly off ≠ holiday |

## 8. Roles and permissions (PRD §3.1, §11)

| ID | Requirement | Screens | Cover | Ph | Planned test |
|---|---|---|---|---|---|
| R-RBAC-01 | Role list, create, duplicate, edit, assign, deactivate | S67, S68, S70 | Covered | 7 | W: system roles not editable |
| R-RBAC-02 | Permissions grouped by module; actions view/create/edit/deactivate/approve/correct/export | S68, S69 | Covered | 7 | U: permission model |
| R-RBAC-03 | Scope org-wide / selected branches / own records | S68, S70 | Covered | 7 | U + B: scope filtering |
| R-RBAC-04 | Owner-only actions protected; no over-delegation | S68 (🔒 cells) | Covered | 7 | U: delegation check |
| R-RBAC-05 | Last owner cannot be removed; high-impact changes confirmed | S70 | Covered | 7 | W: last-owner block; high-impact confirm |
| R-RBAC-06 | Role/permission changes audited; revocation takes effect per policy | S68 warning, S78 | Covered | 7 | B |
| R-RBAC-07 | Front-end navigation is not the boundary (§11) | — | Backend | 1–7 | Route guards in client **and** B tests |
| R-RBAC-08 | Invitation and account status | S71 | Covered | 7 | W: resend/revoke |

## 9. Settings (PRD §12)

| ID | Settings area | Screens | Cover | Ph | Planned test |
|---|---|---|---|---|---|
| R-SET-01 | Organization profile | S35 | Covered | 3 | W |
| R-SET-02 | Branches | S36–S38 | Covered | 3 | W |
| R-SET-03 | Work schedule (breaks, overnight) | S81 | Covered | 7 | U: expected hours minus unpaid breaks |
| R-SET-04 | Attendance policy | S79 | Covered | 7 | W |
| R-SET-05 | Leave policy | S59 | Covered | 6 | W |
| R-SET-06 | Holiday policy | S62–S66 | Covered | 6 | — |
| R-SET-07 | Employee fields | S45 | Covered | 4 | — |
| R-SET-08 | Access & security | S83 | Covered | 7 | W: confirm-it's-you |
| R-SET-09 | Notifications | S82 | Covered | 7 | W |
| R-SET-10 | Data & exports, retention | S84 | Covered | 7 | W |
| R-SET-11 | Branding & localization | S85 | Covered (languages beyond English — Q-15) | 7 | W: contrast warning |
| R-SET-12 | Show who changed a setting and when; prospective vs recalculation | S79 change history, S35 footer | Covered | 7 | U |

## 10. Dashboards (PRD §13)

| ID | Requirement | Screens | Cover | Ph | Planned test |
|---|---|---|---|---|---|
| R-DASH-01 | Admin KPIs: total, active, present, absent/late, working now, pending leave, holidays | S30, S31 | Covered | 4 | U: KPIs derived from data, never hard-coded |
| R-DASH-02 | Charts: trend, distribution, leave by type, headcount, scheduled vs worked | S30 | Covered | 4 | W: empty/partial data states |
| R-DASH-03 | Action panels: approvals, missing punches, imports, onboarding tasks | S30 | Covered | 4 | W |
| R-DASH-04 | Filters update all widgets; click-through to filtered lists | S30 | Covered (filters drawn; click-through partly linked) | 4 | W |
| R-DASH-05 | Data freshness and honest empty states | S30 ("Updated 2 min ago"), S96 | Covered | 4 | W |
| R-DASH-06 | Branch-manager scoped dashboard | S33 | Covered | 4 | U + B scope |
| R-DASH-07 | Employee dashboard | S86 | Covered | 5 | W |

## 11. Notifications, search, exports, audit (PRD §13.3, §14, §15)

| ID | Requirement | Screens | Cover | Ph | Planned test |
|---|---|---|---|---|---|
| R-NOT-01 | In-app notifications for employees, approvers, admins; no sensitive content | S76, S95 | Covered | 7 | W: unread/mark all read |
| R-NOT-02 | Preferences per event/channel | S82 | Covered | 7 | W |
| R-SRCH-01 | Global search scoped to permitted records | S30 top bar | Partial — results UI not drawn | 4 | Q-12 |
| R-RPT-01 | MVP reports: roster, changes, daily, monthly, missing punch, leave balance, leave decisions, holiday calendar, audit log | S73 | Covered | 7 | W: columns not permitted are disabled |
| R-RPT-02 | CSV/XLSX (PDF optional); exports follow scope; logged; formula-injection safe | S73–S75, S84 | Covered (PDF not designed — Q-16) | 7 | U: cell escaping (`=`, `+`, `-`, `@`) |
| R-AUD-01 | Audit events with actor, action, entity, time, scope, before/after, reason | S77, S78 | Covered | 7 | U: event model |
| R-AUD-02 | Append-only; admins view/export but cannot edit | S77, S84 | Covered | 7 | B |

## 12. Non-functional (PRD §16)

| ID | Requirement | Where | Ph | Planned test |
|---|---|---|---|---|
| R-NF-01 | Accessibility: keyboard, labels, contrast, focus, responsive | All; S01 rules | 1–8 | W: semantics labels, focus traversal; contrast of tokens (U) |
| R-NF-02 | Performance: pagination, no loading all records | Lists | 4–7 | U: paged repository |
| R-NF-03 | Tenant isolation | — | 1+ | B (cannot be proven client-side) |
| R-NF-04 | Concurrent edits not silently overwritten | S96 conflict state | 3–7 | U: version check handling |
| R-NF-05 | Input/file security | S13, S46, S65 | 3–6 | U: file-type/size guards |
| R-NF-06 | Time integrity UTC + IANA | — | 1, 5 | U: `timezone` conversions |

## 13. In the design but not in the PRD

| Feature | Screens | Proposed handling |
|---|---|---|
| Progress percentage per branch with weights and drop-on-invalid | S20–S24 | Implement as designed (Phase 3) |
| "Copy from another branch" for setup steps | S21 | Implement |
| Owner profile separate from employee record | S16 | Implement |
| Trusted device 30 days, backup codes | S06 | Implement UI; needs backend support |
| Sealed audit chain (checksum) | S78 | Display only; backend concern |
| Platform super-admin with owner-approved support sessions and suspend | S97, S98 | Optional (PRD marks platform admin optional) — Q-13 |
| Kiosk punch method | S21 attendance panel | Option is selectable but no kiosk UI — Q-10 |
| Gujarati / Hindi UI languages | S85 | Q-15 |

## 14. Out of scope (both documents agree)

Payroll, payslips, tax, benefits, recruitment, performance, assets, expenses, shift rotas, biometric devices, GPS/geofencing, selfie, QR, statutory multi-country automation.
