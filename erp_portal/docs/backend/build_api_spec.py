"""Builds the Staffline backend API specification PDF.

Usage: python build_api_spec.py <fonts dir> <output.pdf>
Needs reportlab. The source of truth is the repository interfaces and
domain models under lib/features/*/domain/.
"""
import sys
from reportlab.lib import colors
from reportlab.lib.pagesizes import A4
from reportlab.lib.styles import ParagraphStyle
from reportlab.lib.units import mm
from reportlab.pdfbase import pdfmetrics
from reportlab.pdfbase.ttfonts import TTFont
from reportlab.platypus import (PageBreak, Paragraph, SimpleDocTemplate,
                                Spacer, Table, TableStyle, KeepTogether)

FONTS, OUT = sys.argv[1], sys.argv[2]
pdfmetrics.registerFont(TTFont('Plex', f'{FONTS}/IBMPlexSans-Regular.ttf'))
pdfmetrics.registerFont(TTFont('Plex-Semi', f'{FONTS}/IBMPlexSans-SemiBold.ttf'))
pdfmetrics.registerFont(TTFont('Mono', f'{FONTS}/IBMPlexMono-Regular.ttf'))
pdfmetrics.registerFont(TTFont('Mono-Medium', f'{FONTS}/IBMPlexMono-Medium.ttf'))
pdfmetrics.registerFontFamily('Plex', normal='Plex', bold='Plex-Semi',
                              italic='Plex', boldItalic='Plex-Semi')

INK = colors.HexColor('#0E1A2B')
MUTED = colors.HexColor('#475467')
PRIMARY = colors.HexColor('#2B4ACB')
SOFT = colors.HexColor('#EEF1FD')
BORDER = colors.HexColor('#E2E5EA')
CODEBG = colors.HexColor('#F5F6F8')
METHOD = {'GET': '#0B7A62', 'POST': '#2B4ACB', 'PUT': '#9A5B00',
          'PATCH': '#9A5B00', 'DELETE': '#B42318'}

body = ParagraphStyle('body', fontName='Plex', fontSize=9.5, leading=14,
                      textColor=INK, spaceAfter=5)
small = ParagraphStyle('small', parent=body, fontSize=8, leading=10.8,
                       spaceAfter=0)
smallb = ParagraphStyle('smallb', parent=small, fontName='Plex-Semi')
mono = ParagraphStyle('mono', parent=small, fontName='Mono', fontSize=7.4,
                      leading=10)
code = ParagraphStyle('code', fontName='Mono', fontSize=7.6, leading=10.4,
                      textColor=INK, backColor=CODEBG, borderPadding=6,
                      leftIndent=6, rightIndent=6, spaceBefore=4,
                      spaceAfter=10)
h1 = ParagraphStyle('h1', fontName='Plex-Semi', fontSize=17, leading=22,
                    textColor=INK, spaceBefore=4, spaceAfter=8)
h2 = ParagraphStyle('h2', fontName='Plex-Semi', fontSize=12, leading=16,
                    textColor=PRIMARY, spaceBefore=10, spaceAfter=4)
h3 = ParagraphStyle('h3', fontName='Plex-Semi', fontSize=10, leading=14,
                    textColor=INK, spaceBefore=6, spaceAfter=3)
bullet = ParagraphStyle('bullet', parent=body, leftIndent=12,
                        bulletIndent=2, spaceAfter=2)

story = []
W = A4[0] - 32 * mm


def P(t, s=body):
    story.append(Paragraph(t, s))


def bullets(items):
    for i in items:
        story.append(Paragraph(i, bullet, bulletText='•'))


def codeblock(text):
    esc = (text.replace('&', '&amp;').replace('<', '&lt;')
           .replace('>', '&gt;').replace(' ', '&nbsp;').replace('\n', '<br/>'))
    story.append(Paragraph(esc, code))


def table(rows, widths, styles=None, extra=None):
    styles = styles or [small] * len(widths)
    data = []
    for r, row in enumerate(rows):
        data.append([c if not isinstance(c, str) else
                     Paragraph(c, smallb if r == 0 else styles[i])
                     for i, c in enumerate(row)])
    t = Table(data, colWidths=widths, repeatRows=1)
    st = [('GRID', (0, 0), (-1, -1), 0.5, BORDER),
          ('VALIGN', (0, 0), (-1, -1), 'TOP'),
          ('BACKGROUND', (0, 0), (-1, 0), SOFT),
          ('TOPPADDING', (0, 0), (-1, -1), 2.5),
          ('BOTTOMPADDING', (0, 0), (-1, -1), 2.5),
          ('LEFTPADDING', (0, 0), (-1, -1), 3.5),
          ('RIGHTPADDING', (0, 0), (-1, -1), 3.5)]
    t.setStyle(TableStyle(st + (extra or [])))
    story.append(t)
    story.append(Spacer(1, 6))


# =====================================================================
# Endpoint catalogue. (method, path, permission, input, output, replaces,
# R = required to replace the demo repositories, N = needed for real
# data volumes / server-side rules)
# =====================================================================
O = '/orgs/{orgId}'
MODULES = []


def module(name, intro, rows, rules):
    MODULES.append((name, intro, rows, rules))


module('Authentication and session', 'Public sign-in flows, plus the '
       'signed-in member\'s session. Replaces <font name="Mono">AuthRepository</font>.', [
    ('POST', '/auth/sign-in', 'Public', 'identifier (work email or employee ID), password, keepSignedIn', 'account, requiresTwoStep, challengeToken (if two-step) or tokens', 'signIn', 'R'),
    ('POST', '/auth/two-step/verify', 'challengeToken', 'code, isBackupCode, trustDevice', 'tokens, backupCodesLeft (when a backup code was used)', 'verifyTwoStep', 'R'),
    ('POST', '/auth/refresh', 'Refresh cookie', '—', 'new access token (rotates refresh token)', '—', 'R'),
    ('POST', '/auth/sign-out', 'Signed in', '—', '204; refresh token revoked', '—', 'R'),
    ('POST', '/auth/reauthenticate', 'Signed in', 'password', 'reauthToken (5 min), sent as <font name="Mono">X-Reauth</font> on sensitive saves', '"Confirm it\'s you"', 'R'),
    ('POST', '/auth/register', 'Public', 'fullName, email, password, phone?', '202; 6-digit code emailed', 'register', 'R'),
    ('POST', '/auth/verify-email', 'Public', 'email, code', 'account + tokens', 'verifyEmail', 'R'),
    ('POST', '/auth/verify-email/resend', 'Public', 'email', '202', 'resendVerificationCode', 'R'),
    ('POST', '/auth/password/forgot', 'Public', 'identifier', 'Always 202 (never reveals if the account exists)', 'requestPasswordReset', 'R'),
    ('GET', '/auth/password/reset/{token}', 'Public', '—', 'maskedEmail', 'openResetLink', 'R'),
    ('POST', '/auth/password/reset', 'Public', 'token, newPassword', '204', 'resetPassword', 'R'),
    ('GET', '/auth/invitations/{token}', 'Public', '—', 'Invitation', 'openInvitation', 'R'),
    ('POST', '/auth/invitations/{token}/accept', 'Public', 'password', 'account + tokens', 'acceptInvitation', 'R'),
    ('GET', '/me', 'Signed in', '—', 'UserAccount', 'accountById', 'R'),
    ('GET', '/me/memberships', 'Signed in', '—', 'OrganizationMembership[]', 'membershipsOf', 'R'),
    ('PUT', '/me/last-organization', 'Signed in', 'organizationId', '204', 'rememberLastOrganization', 'R'),
    ('GET', O + '/session', 'Member of org', '—', 'AppSession (role, grants, scope, branchIds, employeeId)', 'session building', 'R'),
    ('POST', O + '/access-requests', 'Member of org', 'path (page that was refused)', 'ownerName', 'requestAccess', 'R'),
], [
    'Wrong sign-in details return one generic message that never reveals whether the account exists.',
    'Two-step is required by the organization\'s policy (Security settings: optional / admins / everyone). Default: Owner, HR Admin, Branch Manager, Attendance Manager.',
    'Three wrong codes or <font name="Mono">lockAfterAttempts</font> wrong passwords lock sign-in for <font name="Mono">lockMinutes</font> (default 15). Respond 423 with <font name="Mono">until</font>.',
    'Reset links: one use, valid <font name="Mono">resetMinutes</font> (default 30). Invitations valid <font name="Mono">inviteDays</font> (default 7). Expired or used → 410.',
    'Password rules: at least 10 characters (or the organization minimum, 8–64), a number, upper and lower case letters, and not containing the person\'s name or email. Hash with Argon2id or bcrypt.',
    '"Trust this device" lasts 30 days. Backup codes are single-use.',
    'Idle timeout (<font name="Mono">adminIdleMinutes</font>, <font name="Mono">employeeIdleDays</font>) and session length are enforced by token lifetimes.',
    'A deactivated membership cannot be opened (403).',
])

module('Organization and branches', 'Replaces <font name="Mono">OrganizationRepository</font>.', [
    ('POST', '/orgs', 'Signed in, verified email', 'name, employeeRange, logo? (upload id)', 'Organization; caller becomes Owner', 'createOrganization', 'R'),
    ('GET', O, 'organization.view (all members get name + logo)', '—', 'Organization', 'organization', 'R'),
    ('PUT', O, 'organization.edit', 'Organization fields + version', 'Organization', 'updateOrganization', 'R'),
    ('GET', O + '/owner-profile', 'organization.edit', '—', 'OwnerProfile or 204', 'ownerProfile', 'R'),
    ('PUT', O + '/owner-profile', 'organization.edit', 'OwnerProfile', 'OwnerProfile', 'saveOwnerProfile', 'R'),
    ('GET', O + '/branches', 'organization.view (scoped)', 'status?', 'Branch[] (only branches in scope)', 'branches', 'R'),
    ('GET', O + '/branches/{branchId}', 'organization.view (scoped)', '—', 'Branch; 404 if out of scope', '—', 'R'),
    ('POST', O + '/branches', 'organization.edit', 'Branch (basics)', 'Branch', 'createBranch', 'R'),
    ('PUT', O + '/branches/{branchId}', 'organization.edit', 'Branch (any section: hours, attendance, holidays, leave, roles, reminders) + version', 'Branch', 'updateBranch', 'R'),
    ('POST', O + '/branches/{branchId}/status', 'organization.edit', 'status (active | inactive)', 'Branch; 409 while employees are assigned', 'setBranchStatus', 'R'),
    ('GET', O + '/setup-bookmark', 'organization.edit', '—', 'SetupBookmark or 204', 'setupBookmark', 'R'),
    ('PUT', O + '/setup-bookmark', 'organization.edit', 'branchId, step', '204', 'saveSetupBookmark', 'R'),
], [
    'Branch name and code are unique within the organization (409 / field error). Branch and organization phones: 10 digits including the area code, not starting 0/1. PIN: 6 digits, not starting 0.',
    'PIN code is 6 digits; each open day closes after it opens; at least one open day.',
    '<font name="Mono">employeeCount</font> is computed from employee records (inactive included, terminated excluded), never stored.',
    'Branch time zone is an IANA id; null means "inherit organization time zone" (default Asia/Kolkata).',
    'Setup progress is computed from saved data (weights basics 25, attendance 20, holidays 15, leave 20, roles 15, reminders 5) — the server may return it as <font name="Mono">setupPercent</font>.',
])

module('Employees, custom fields and import', 'Replaces <font name="Mono">EmployeeRepository</font>.', [
    ('GET', O + '/employees', 'employees.view (scoped)', 'search, branchId, department, status, type, sort (name | department | joined | code), ascending, page, pageSize', 'Page&lt;Employee&gt; (masked restricted fields)', 'employees', 'R'),
    ('GET', O + '/employees/{id}', 'employees.view (scoped)', '—', 'Employee incl. activity; 404 if out of scope', 'employees', 'R'),
    ('POST', O + '/employees', 'employees.create', 'Employee fields, sendInvite', 'Employee', 'create', 'R'),
    ('PUT', O + '/employees/{id}', 'employees.edit', 'Employee fields + version, notes[]', 'Employee', 'update', 'R'),
    ('POST', O + '/employees/{id}/status', 'employees.deactivate', 'status, reason, lastWorkingDay?', 'Employee', 'setStatus', 'R'),
    ('POST', O + '/employees/branch-move', 'employees.edit', 'employeeIds[], branchId, managerId?, effectiveFrom', 'movedCount', 'changeBranch', 'R'),
    ('POST', O + '/employees/invitations/resend', 'employees.create', 'employeeIds[]', 'sentCount (signed-in people skipped)', 'resendInvites', 'R'),
    ('POST', O + '/employees/{id}/password-reset', 'employees.edit', '—', '202; reset link emailed', 'sendPasswordReset', 'R'),
    ('GET', O + '/me/profile', 'Self', '—', 'Own Employee record', 'selfEmployee', 'R'),
    ('PATCH', O + '/me/profile', 'Self', 'mobile, emergencyContact, preferredLanguage (per member)', 'Employee', 'My profile edit', 'R'),
    ('PUT', O + '/employees/{id}/photo', 'employees.edit or self', 'upload id', 'Employee', 'photo upload', 'R'),
    ('GET', O + '/departments', 'Signed in', '—', 'string[] (today a fixed list in the app)', '—', 'N'),
    ('GET', O + '/employee-field-settings', 'Signed in (forms need it)', '—', 'EmployeeFieldSettings', 'fieldSettings', 'R'),
    ('PUT', O + '/employee-field-settings', 'employeeFields.edit', 'rules {field: required | optional | hidden} + version', 'EmployeeFieldSettings', 'saveFieldSettings', 'R'),
    ('GET', O + '/custom-fields', 'employees.view', 'includeArchived?', 'CustomField[]', 'customFields', 'R'),
    ('POST', O + '/custom-fields', 'employeeFields.edit', 'CustomField', 'CustomField', 'saveCustomField', 'R'),
    ('PUT', O + '/custom-fields/{id}', 'employeeFields.edit', 'CustomField, renamedOptions {old: new}', 'CustomField', 'saveCustomField', 'R'),
    ('PUT', O + '/custom-fields/order', 'employeeFields.edit', 'fieldIds[]', '204', 'reorderCustomFields', 'R'),
    ('POST', O + '/employee-imports/validate', 'importExport.create + employees.create', 'file (upload id) or rows, mapping, dateOrder, duplicatePolicy', 'ImportPlan (per-row result and messages)', 'client-side today', 'N'),
    ('POST', O + '/employee-imports', 'importExport.create + employees.create (+ employees.edit to update)', 'fileName, plan rows, skipped[], sendInvites', 'ImportRecord', 'commitImport', 'R'),
    ('GET', O + '/employee-imports', 'importExport.view', '—', 'ImportRecord[]', 'imports', 'R'),
    ('GET', O + '/employee-imports/{id}', 'importExport.view', '—', 'ImportRecord', 'imports', 'R'),
    ('GET', O + '/employee-imports/{id}/error-report', 'importExport.view', '—', '.xlsx file', 'client-side today', 'N'),
    ('GET', O + '/employee-imports/template', 'importExport.create', '—', '.xlsx template', 'client-side today', 'N'),
], [
    'One validator for create, edit and import. Field errors use the keys below in <font name="Mono">fieldErrors</font>.',
    '<font name="Mono">code</font>: required, upper-cased, <font name="Mono">^[A-Z0-9][A-Z0-9-]{1,19}$</font>, unique. <font name="Mono">workEmail</font>: valid, unique; required only when an invitation is sent.',
    '<b>Field settings (D-73):</b> built-in fields follow the organization\'s rules. Locked as required (422 if a rule tries to change them): code, firstName, lastName, branchId, joiningDate, type, shift, managerId. workEmail may be required or optional, never hidden; probation and weeklyOff optional or hidden. A required field that is empty → <font name="Mono">fieldErrors[key] = "Enter …"</font>; hidden fields are not required and keep saved values. personalEmail, dateOfBirth and emergencyContact are only enforced for callers who can see restricted fields. Imports apply the same rules; required fields with no import column become row warnings.',
    '<font name="Mono">mobile</font>: Indian mobile — 10 digits starting 6–9 after removing +91 / 91 / 0, spaces, dashes and brackets; store normalized as +91XXXXXXXXXX. firstName/lastName: letters (any script), space . \' -, max 50. personalEmail must differ from workEmail. emergencyContact: must contain a name and a valid phone, not the employee\'s own mobile, max 80. dateOfBirth: not future, age ≥ 18 on joiningDate, ≤ 80. joiningDate ≤ today + 6 months. designation 2–60 chars with a letter (D-78).',
    '<font name="Mono">personalEmail</font>: valid if given. <font name="Mono">designation</font> and <font name="Mono">department</font> (from the list) required by default; <font name="Mono">branchId</font> (active branch) always required. <font name="Mono">shift</font> must be one of the branch\'s shifts.',
    '<font name="Mono">managerId</font> is required (except HR Admin and Branch Manager, who may report to the owner), must be employed, and must work at the same branch.',
    'Custom fields: <font name="Mono">custom.&lt;key&gt;</font> errors; required fields enforced; per-audience view/edit access (hrAdmin, branchManager, attendanceManager, self) applied when reading and writing.',
    'Someone who still manages employed people cannot be deactivated or terminated (409). Terminated people are excluded from default lists and head counts but keep all history.',
    'Branch managers can only create people in, and move people within, their own branches.',
    'Import: duplicates matched by employee ID. "Update existing" changes only mapped, non-empty columns and never branch, manager or joining date. Ambiguous dates must be rejected unless <font name="Mono">dateOrder</font> is given. Each row is saved on its own and re-checked; a failed row is listed, never half-saved.',
    'Every change appends to the employee\'s activity (<font name="Mono">created | updated | moved | status | account</font>) and to the audit log.',
])

module('Attendance', 'Replaces <font name="Mono">AttendanceRepository</font>. Today the app loads raw data and '
       'calculates day records itself (<font name="Mono">AttendanceBook</font>); with real volumes the '
       'server should return calculated days.', [
    ('GET', O + '/attendance', 'attendance.view (scoped) or self', 'from, to, branchId?, employeeId?', 'AttendanceData: punches, corrections, requests, reminders', 'load', 'R'),
    ('POST', O + '/attendance/punches', 'Self (own employee record)', 'multipart: kind (punchIn | punchOut | breakStart | breakEnd), source (app | web | kiosk), selfie (JPEG, required when the branch has selfieCheck and the person isn\'t exempt); header Idempotency-Key = requestId', 'Punch (server time) incl. face {result, score}', 'punch', 'R'),
    ('POST', O + '/attendance/corrections', 'attendance.correct (scoped)', 'employeeId, workDate, changes[] {kind, at, replaces?}, reason, requestId?', 'Correction (approved, or pending when a second approval is needed)', 'correct', 'R'),
    ('POST', O + '/attendance/corrections/{id}/decision', 'attendance.approve (not own)', 'approve, note?', 'Correction', 'decide', 'R'),
    ('POST', O + '/attendance/correction-requests', 'Self', 'workDate, kind, proposedAt, message', 'CorrectionRequest', 'request', 'R'),
    ('POST', O + '/attendance/correction-requests/{id}/reject', 'attendance.correct (scoped)', 'reason', 'CorrectionRequest', 'rejectRequest', 'R'),
    ('POST', O + '/attendance/reminders', 'attendance.correct (scoped)', 'items[] {employeeId, workDate}', 'sentCount', 'remind', 'R'),
    ('GET', O + '/attendance/face-reviews', 'attendance.approve (scoped)', 'status (waiting | decided), branchId?, cursor', 'punches to review with selfie and enrolled photo URLs', 'punchesToReview', 'R'),
    ('POST', O + '/attendance/punches/{punchId}/face-review', 'attendance.approve (scoped, not own)', 'accept, note (required to reject, ≥ 3 chars)', 'FaceReview', 'reviewFacePunch', 'R'),
    ('PUT', O + '/me/face', 'Self', 'multipart: consent = true, photos[3] (JPEG)', 'FaceProfile (pending)', 'enrolFace', 'R'),
    ('DELETE', O + '/me/face', 'Self', '—', '204; face data and templates deleted', 'deleteFace', 'R'),
    ('POST', O + '/employees/{id}/face/decision', 'Owner or HR Admin (organization scope + employees.edit), not own', 'approve, reason (required to reject)', 'FaceProfile', 'decideFace', 'R'),
    ('PUT', O + '/employees/{id}/face-exemption', 'Owner or HR Admin', 'reason (≥ 3 chars), or null to end it', 'FaceExemption or 204', 'setFaceExemption', 'R'),
    ('GET', O + '/attendance/days', 'attendance.view (scoped) or self', 'date or from/to, branchId?, department?, employeeId?, exceptionsOnly?', 'DayRecord[] + AttendanceCounts', 'AttendanceBook (client today)', 'N'),
    ('GET', O + '/attendance/monthly', 'attendance.view (scoped)', 'month, branchId?, department?', 'per-employee month grid + totals', 'Monthly summary (client today)', 'N'),
    ('GET', O + '/attendance/missing-punches', 'attendance.view (scoped)', 'branchId?, overdueOnly?', 'open sessions with age', 'Missing punches (client today)', 'N'),
], [
    'Original punches are never edited or deleted. A correction adds events (or replaces one by <font name="Mono">replaces</font> id) and counts only when approved.',
    'A correction made by the employee\'s own manager needs a second approver (HR). Nobody approves their own correction (403).',
    'Employees may request a correction only within 3 days of the work day, one open request per day.',
    'Punch time is the server clock in UTC, never the device clock. A second punch-in while a session is open → 409. Retrying with the same Idempotency-Key returns the original punch.',
    'Work days are grouped in the branch\'s time zone. Night shift: punches before noon belong to the previous day. A punch-out more than 20 h after punch-in starts a new session with a missing punch-in.',
    'Day status order: missing punch → half day (late beyond <font name="Mono">halfDayLateMinutes</font>, default 120, or worked ≤ half of expected) → left early (<font name="Mono">earlyLeaveMinutes</font>, 30) → short shift (>1 h short) → late (after <font name="Mono">graceMinutes</font>, 10) → present. Expected = shift minus a 60-minute break.',
    'Approved full-day leave turns an unpunched scheduled day into "on leave"; punches on a leave day win.',
    '<b>Selfie punches (D-70):</b> when the branch has <font name="Mono">attendance.selfieCheck</font> and the person has no exemption, a punch without a selfie → 422. The server runs face detection, a passive liveness check and 1:1 matching against the approved enrolment. Results: <font name="Mono">verified</font> (above the match threshold), <font name="Mono">notMatched</font>, <font name="Mono">noFace</font> (no face or liveness failed), <font name="Mono">notEnrolled</font>. The punch is <b>always saved</b>; anything but verified waits for review.',
    'A face review is final (409 if repeated). A rejected punch is excluded from every calculation and export; the original punch and the review stay in the audit trail.',
    '<b>Enrolment (D-71):</b> requires <font name="Mono">consent = true</font> and three photos; replaces any earlier enrolment and sets it back to pending. Only Owner/HR approve; nobody approves their own. Deleting removes photos and face templates immediately.',
    'Store face templates and photos encrypted, separate from other employee data; never return them in employee lists or exports. Only reviewers in scope and the employee can view a selfie, and each view is audited. Punch selfies are deleted after 90 days.',
])

module('Leave', 'Replaces <font name="Mono">LeaveRepository</font>. The server must apply the same routing, '
       'counting and self-approval rules as <font name="Mono">LeaveBook</font> in the app.', [
    ('GET', O + '/leave/types', 'Signed in', 'includeInactive?', 'LeaveType[]', 'load', 'R'),
    ('POST', O + '/leave/types', 'leave.edit', 'LeaveType', 'LeaveType', 'saveType', 'R'),
    ('PUT', O + '/leave/types/{key}', 'leave.edit', 'LeaveType', 'LeaveType', 'saveType', 'R'),
    ('GET', O + '/leave/policy', 'leave.view', '—', 'LeavePolicy', 'load', 'R'),
    ('PUT', O + '/leave/policy', 'leave.edit', 'LeavePolicy + version', 'LeavePolicy', 'savePolicy', 'R'),
    ('GET', O + '/leave/requests', 'leave.view (scoped) or self', 'status?, typeKey?, branchId?, employeeId?, from?, to?, search?, page', 'Page&lt;LeaveRequest&gt;', 'load', 'R'),
    ('GET', O + '/leave/requests/{id}', 'leave.view (scoped) or self', '—', 'LeaveRequest', 'load', 'R'),
    ('POST', O + '/leave/requests/preview', 'Self', 'typeKey, from, to, half', 'days, balanceAfter, approvers, teamOff, blockingErrors[]', 'LeaveBook (client today)', 'N'),
    ('POST', O + '/leave/requests', 'Self', 'typeKey, from, to, half, reason', 'LeaveRequest with routed steps', 'submit', 'R'),
    ('PUT', O + '/leave/requests/{id}', 'Self (pending or changes requested)', 'typeKey, from, to, half, reason', 'LeaveRequest (back to pending; amendedFrom kept)', 'amend', 'R'),
    ('POST', O + '/leave/requests/{id}/decision', 'leave.approve, assigned step, not own', 'approve, note (required to reject, ≥ 3 chars)', 'LeaveRequest', 'decide', 'R'),
    ('POST', O + '/leave/requests/{id}/request-changes', 'leave.approve, assigned step', 'note', 'LeaveRequest', 'requestChanges', 'R'),
    ('POST', O + '/leave/requests/{id}/withdraw', 'Self (pending)', '—', 'LeaveRequest', 'withdraw', 'R'),
    ('POST', O + '/leave/requests/{id}/cancel', 'Self (approved, not started, policy allows)', '—', 'LeaveRequest', 'cancel', 'R'),
    ('GET', O + '/leave/adjustments', 'leave.view (scoped)', 'employeeId?, year?', 'LeaveAdjustment[]', 'load', 'R'),
    ('POST', O + '/leave/adjustments', 'leave.edit', 'employeeId, typeKey, days (±), effective, reason, carry', 'LeaveAdjustment', 'adjust', 'R'),
    ('GET', O + '/leave/balances', 'leave.view (scoped) or self', 'year, employeeId?, branchId?, search?', 'per employee: LeaveBalance[]', 'LeaveBook (client today)', 'N'),
], [
    'Balance = granted (upfront and prorated, or accrued monthly after <font name="Mono">startsAfterMonths</font>) + carried + adjustments − approved − pending. Never stored as one number.',
    'Days are counted from the work calendar: weekly offs and holidays are skipped unless the type counts them. Adding a holiday later gives approved days back.',
    'Routing: step 1 = reporting manager (HR when the branch approves centrally, or no manager). Optional step 2 from the most specific route: type › branch › default (<font name="Mono">SecondStep</font>: none, hrIfDays, branchManagerIfDays, hrAlways).',
    'Nobody is routed to, or may decide, their own request — such a step goes to HR. HR never decides the same request twice.',
    'Who decides: Owner/HR any pending step except their own; Branch Manager any request in their branches; Leave Approver only steps assigned to them.',
    'Validation: type eligibility (employment type, branch, department), min/max days, half days allowed, notice days, backdating (≤ <font name="Mono">backdateDays</font>, max 30), longest request, blackout dates, negative balance only if <font name="Mono">allowNegative</font> and within <font name="Mono">negativeLimit</font>.',
    'Optional holidays use a type with <font name="Mono">optionalHolidaysOnly</font>, limited to <font name="Mono">optionalHolidaysPerYear</font> (default 1).',
])

module('Holidays and schedules', 'Replaces <font name="Mono">CalendarRepository</font>. Branch holiday lists from setup stay on the branch.', [
    ('GET', O + '/holidays', 'Signed in (filtered to own branch for employees)', 'year, branchId?', 'CompanyHoliday[]', 'holidays', 'R'),
    ('POST', O + '/holidays', 'holidays.create', 'CompanyHoliday', 'CompanyHoliday + affectedLeaveRequests', 'saveHoliday', 'R'),
    ('PUT', O + '/holidays/{id}', 'holidays.create', 'CompanyHoliday', 'CompanyHoliday', 'saveHoliday', 'R'),
    ('DELETE', O + '/holidays/{id}', 'holidays.create', '—', '204', 'deleteHoliday', 'R'),
    ('POST', O + '/holidays/import', 'holidays.create', 'rows[] CompanyHoliday', 'CompanyHoliday[]', 'importHolidays', 'R'),
    ('GET', O + '/schedule-assignments', 'holidays.view', 'level?, branchId?', 'ScheduleAssignment[]', 'assignments', 'R'),
    ('POST', O + '/schedule-assignments', 'holidays.create', 'ScheduleAssignment', 'ScheduleAssignment', 'addAssignment', 'R'),
], [
    'Past holidays cannot be added, edited or deleted (409). Range up to 14 days. Overlapping holidays for the same branch are refused.',
    'Scope: <font name="Mono">branchIds</font> empty = all branches; <font name="Mono">optional</font> = optional holiday.',
    'Schedules: most specific assignment in effect wins (employee › group › branch › organization); a person\'s own weekly off beats group/branch. <font name="Mono">effectiveFrom</font> cannot be in the past.',
])

module('Roles and access', 'Replaces <font name="Mono">AccessRepository</font>.', [
    ('GET', O + '/roles', 'roles.view', '—', 'RoleDefinition[] with holder counts', 'load', 'R'),
    ('GET', O + '/roles/{id}', 'roles.view', '—', 'RoleDefinition', 'load', 'R'),
    ('POST', O + '/roles', 'roles.create + X-Reauth', 'RoleDefinition, reason', 'RoleDefinition', 'saveRole', 'R'),
    ('PUT', O + '/roles/{id}', 'roles.edit + X-Reauth', 'RoleDefinition + version, reason', 'RoleDefinition', 'saveRole', 'R'),
    ('GET', O + '/role-assignments', 'roles.view', 'roleId?, search?', 'members with role, scope, branchIds, teamSize', 'load', 'R'),
    ('PUT', O + '/role-assignments/{memberKey}', 'roles.edit', 'roleId, branchIds[], reason', 'RoleAssignment', 'assign', 'R'),
    ('GET', O + '/invitations', 'employees.create (scoped)', 'state (waiting | expired | bounced | accepted)', 'invitation rows', 'Invitations page', 'R'),
    ('DELETE', O + '/invitations/{memberKey}', 'employees.create', '—', '204 (revoke)', 'revoke', 'R'),
    ('DELETE', O + '/invitations/{memberKey}/bounce', 'employees.create', '—', '204', 'clearBounce', 'R'),
], [
    'System roles (owner, hrAdmin, leaveApprover, employee) are read-only; they can be duplicated.',
    'Owner-only permissions (organization create/deactivate, roles create/edit/deactivate) cannot be granted to any other role (422).',
    'The last owner cannot lose the Owner role (409).',
    'A branch-scoped role needs at least one branch.',
    'Changing a role updates the employee record (for leave routing) and takes effect on the member\'s next request: re-issue or invalidate their access token.',
])

module('Settings', 'Replaces <font name="Mono">SettingsRepository</font>.', [
    ('GET', O + '/settings', 'settings.view', '—', 'OrgSettings (security, data, branding)', 'load', 'R'),
    ('PUT', O + '/settings/security', 'Owner + X-Reauth', 'SecuritySettings', 'SecuritySettings', 'save', 'R'),
    ('PUT', O + '/settings/data', 'Owner', 'DataSettings', 'DataSettings', 'save', 'R'),
    ('PUT', O + '/settings/branding', 'settings.edit', 'BrandingSettings', 'BrandingSettings', 'save', 'R'),
    ('PUT', O + '/settings/attendance', 'settings.edit', 'per-branch AttendanceRules', 'Branch[]', 'branch rules', 'R'),
], [
    '<font name="Mono">minPasswordLength</font> 8–64; <font name="Mono">inviteDays</font>, <font name="Mono">resetMinutes</font>, lock-out and idle values must be positive.',
    'Security and Data & export are owner-only (D-58).',
])

module('Notifications', 'Replaces <font name="Mono">NotificationRepository</font>. <font name="Mono">send</font>, '
       '<font name="Mono">queueEmail</font> and <font name="Mono">outbox</font> become server-internal.', [
    ('GET', O + '/me/notifications', 'Signed in', 'category?, unreadOnly?, cursor', 'AppNotification[] + unreadCount', 'inbox', 'R'),
    ('POST', O + '/me/notifications/read', 'Signed in', 'id? (none = mark all read)', '204', 'markRead', 'R'),
    ('GET', O + '/notification-prefs', 'settings.view', '—', 'NotificationPrefs', 'prefs', 'R'),
    ('PUT', O + '/notification-prefs', 'settings.edit', 'NotificationPrefs', 'NotificationPrefs', 'savePrefs', 'R'),
], [
    'Notifications are created by the server from the same mutations (leave submitted/decided/withdrawn, missing punch, correction decided, repeated lateness, invitation, profile changed, invite bounced, holiday soon/added).',
    'Delivery follows the preference matrix (event × employee/manager/HR × in-app/email). Nobody is notified about their own action. No passwords, attachments or restricted fields in any message.',
])

module('Audit log', 'Replaces <font name="Mono">AuditRepository</font>. <font name="Mono">record</font> becomes server-internal: '
       'every mutating endpoint writes its own entry.', [
    ('GET', O + '/audit-events', 'auditLog.view', 'days, actor?, areas[]?, entityType?, branchId?, search?, cursor', 'AuditEvent[] (masked)', 'events', 'R'),
    ('GET', O + '/audit-events/{id}', 'auditLog.view', '—', 'AuditEvent + related events', 'events', 'R'),
    ('POST', O + '/audit-events/{id}/reveal', 'Owner', 'field, reason', 'unmasked value (the reveal is itself logged)', 'reveal', 'R'),
    ('GET', O + '/audit-events/verify', 'auditLog.view', 'from?, to?', 'chain ok / first broken id', 'chain check', 'R'),
], [
    'Append-only: no update or delete endpoint exists. Each entry stores <font name="Mono">previousHash</font> and <font name="Mono">hash</font> (SHA-256 over the canonical entry + previous hash).',
    'Each entry: who (name, role), what (action, entity, before/after changes), when, scope (branch), reason, source (web | import | system | kiosk), masked IP.',
    'Contact details, IDs, dates of birth and IPs are masked when read or exported.',
])

module('Reports, exports and dashboards', 'Replaces <font name="Mono">ReportRepository</font>. Today reports are '
       'built in the app from loaded data; a backend should build them.', [
    ('GET', O + '/reports/{kind}', 'reports.view + module view', 'from, to, branchId?, department?, columns[]', 'ReportTable (headers, rows, totals, note)', 'client today', 'N'),
    ('POST', O + '/exports', 'see export rule', 'source (report kind, employees, attendance, leaveRequests, leaveBalances, holidays, audit), filters, columns, format (csv | xlsx)', 'ExportRecord (status, download url)', 'add', 'R'),
    ('GET', O + '/exports', 'reports.view', 'cursor', 'ExportRecord[] (own scope)', 'exports', 'R'),
    ('GET', O + '/exports/{id}/download', 'requester or same scope', '—', 'file (logged)', 'download', 'R'),
    ('GET', O + '/dashboard/overview', 'reports.view', 'branchId?, period (last14 | thisMonth | last30)', 'DashboardMetrics + attendance trend + leave by type', 'client today', 'N'),
    ('GET', O + '/dashboard/branch/{branchId}', 'reports.view (scoped)', 'date?', 'today by department, coverage, pending leave', 'client today', 'N'),
], [
    'Report kinds: roster, changes, daily, monthly, missing, balances, requests, holidays, audit (audit: Owner and HR Admin only).',
    'Export needs: module view + export, reports.export for reports, the Data & export right for the area (people, attendance, leave), and for restricted columns (mobile, personal email) the restricted right plus organization scope.',
    'Rows limited to the requester\'s scope. Every export and every download is audited. Files expire after <font name="Mono">linkDays</font> / <font name="Mono">exportFileDays</font>.',
    'Use the organization\'s data settings: date format (dmy | iso), durations (hoursMinutes | decimal), CSV separator.',
])

module('Platform statistics (super admin)', 'Statistics-only operator view (D-75, boards S97–S98). Replaces <font name="Mono">PlatformRepository</font>. Not under <font name="Mono">/orgs/{orgId}</font>: the caller has no organization.', [
    ('GET', '/platform/overview', 'Platform admin', '—', 'Platform totals, daily active (30 days), sign-ups per month (12), feature use, counts by industry and state (no leave-request tile)', 'snapshot', 'R'),
    ('GET', '/platform/organizations', 'Platform admin', 'search?, status (active | settingUp | quiet)?, sort, page', 'Page&lt;OrgStats&gt; (no branches)', 'snapshot', 'R'),
    ('GET', '/platform/organizations/{orgId}', 'Platform admin', '—', 'OrgStats with BranchStats[] and dailyActive[30]', 'snapshot', 'R'),
], [
    'The platform admin is an account flag (<font name="Mono">isPlatformAdmin</font>) with two-step always on and <b>no</b> organization membership; every <font name="Mono">/orgs/{orgId}/*</font> endpoint returns 403 for it, and <font name="Mono">/platform/*</font> returns 403 for everyone else.',
    '<b>Aggregates only:</b> responses may contain counts, percentages and the organization\'s own business details (name, ID, industry, city, state, size range, created date). They must never contain owner or employee names, emails, phones, IDs, photos or individual records. Build the responses from aggregate queries or a reporting view, not by filtering full records in code.',
    'Status: settingUp when an organization has no employed people or no fully set-up active branch; quiet when no punch in 7 days; otherwise active.',
    'Every platform request is written to a platform audit log (who, when, which endpoint).',
])
module('Files', 'Uploads used by organization logo, owner photo and employee photos.', [
    ('POST', O + '/uploads', 'Signed in', 'multipart file, purpose (logo | ownerPhoto | employeePhoto | employeeImport | holidayImport)', 'uploadId, url', 'file_picker uploads', 'R'),
], [
    'Images: PNG or JPG only, ≤ 2 MB, checked by the file\'s first bytes (renamed files refused); SVG refused. Imports: .xlsx or .csv.',
    'Scan uploads for malware; serve images from signed URLs.',
])

# =====================================================================
# Data models (JSON). type notes: string, int, number (decimal),
# bool, date (YYYY-MM-DD), datetime (ISO 8601 UTC), enum, [] = array.
# =====================================================================
MODELS = [
    ('UserAccount', [('id', 'string', 'Account id'), ('fullName', 'string', ''), ('email', 'string', ''), ('employeeId', 'string?', 'Employee code when linked, e.g. EMP-0229')]),
    ('OrganizationMembership', [('organizationId', 'string', ''), ('organizationName', 'string', ''), ('role', 'enum SystemRole', ''), ('branchIds', 'string[]', 'Empty = all'), ('scopeLabel', 'string', 'e.g. "Surat, Vadodara"'), ('summary', 'string', 'e.g. "3 branches · 248 employees"'), ('status', 'enum', 'active | deactivated'), ('lastUsed', 'bool', '')]),
    ('AppSession', [('userId', 'string', ''), ('displayName', 'string', ''), ('email', 'string', ''), ('organizationId / organizationName', 'string', ''), ('role', 'enum SystemRole', 'Base role (sets menu and home)'), ('roleId / roleTitle', 'string?', 'Custom role'), ('grants', 'string[]', 'Permission keys "module.action"'), ('scope', 'enum DataScope', ''), ('scopeLabel', 'string', ''), ('branchIds', 'string[]', ''), ('employeeId', 'string?', ''), ('canSwitchOrganization', 'bool', '')]),
    ('Invitation', [('token', 'string', ''), ('inviterName', 'string', ''), ('organizationName', 'string', ''), ('role', 'enum SystemRole', ''), ('branchName', 'string', ''), ('fullName', 'string', ''), ('employeeId', 'string', ''), ('email', 'string', ''), ('startDate', 'date', ''), ('expiresAt', 'datetime', '')]),
    ('Organization', [('id', 'string', ''), ('name', 'string', 'Display name'), ('employeeRange', 'string', 'e.g. "201–500"'), ('logoUrl', 'string?', 'Upload'), ('legalName', 'string', ''), ('industry', 'string', ''), ('registrationNumber', 'string', 'Masked when read'), ('contactEmail / contactPhone', 'string', ''), ('address, city, state, pin, country', 'string', ''), ('timeZone', 'string', 'IANA, default Asia/Kolkata'), ('createdAt / updatedAt', 'datetime', ''), ('updatedBy', 'string', ''), ('version', 'int', 'Optimistic locking')]),
    ('OwnerProfile', [('fullName, email, phone, designation', 'string', ''), ('photoUrl', 'string?', '')]),
    ('SetupBookmark', [('branchId', 'string', ''), ('step', 'string', 'basics | attendance | holidays | leave | roles | reminders | review')]),
    ('Branch', [('id', 'string', ''), ('name', 'string', 'Unique'), ('code', 'string', 'Unique, e.g. SUR-01'), ('address, city, state', 'string', ''), ('pin', 'string', '6 digits'), ('phone, email', 'string', ''), ('timeZone', 'string?', 'Null = inherit'), ('hours', 'DayHours[7]', 'Mon–Sun: {open, opensAt, closesAt} minutes after midnight'), ('status', 'enum', 'active | inactive'), ('employeeCount', 'int', 'Computed'), ('attendance', 'AttendanceRules?', '{method: app|kiosk|both, graceMinutes 10, earlyLeaveMinutes 30, halfDayLateMinutes 120, shiftMode: branchHours|several, selfieCheck: false}'), ('holidays', 'HolidaySetup?', '{source: gujarat|national|none, items: HolidayItem[]}'), ('leave', 'LeaveSetup?', '{types: [{key, name, daysPerYear, accrual, enabled, tracksBalance}], approval: manager|managerThenHr|owner}'), ('roles', 'RolesSetup?', '{manager: owner|invite, managerEmail, managerCanApproveLeave, managerCanCorrectAttendance, managerCanSeeReports, managerCanEditPeople, employeesCanRequestLeave, employeesCanSeeTeamOff}'), ('reminders', 'ReminderSettings?', '{punchInReminder, missingPunchSummary, weeklyLeaveDigest}'), ('reviewed', 'bool', 'Setup review done'), ('openedOn', 'date?', ''), ('version', 'int', '')]),
    ('HolidayItem (branch)', [('name', 'string', ''), ('date', 'date', ''), ('observed', 'bool', ''), ('custom', 'bool', ''), ('everyYear', 'bool', ''), ('category', 'enum', 'festival | national | regional | company'), ('optional', 'bool', ''), ('orgWide', 'bool', ''), ('description', 'string', '')]),
    ('Employee', [('id', 'string', ''), ('code', 'string', 'Employee ID, unique'), ('firstName, lastName, displayName', 'string', ''), ('workEmail', 'string', 'Unique'), ('mobile', 'string', 'Restricted'), ('personalEmail', 'string', 'Restricted'), ('dateOfBirth', 'date?', 'Masked'), ('emergencyContact', 'string', ''), ('designation', 'string', ''), ('department', 'string', 'From departments list'), ('type', 'enum', 'fullTime | partTime | contract | trainee'), ('joiningDate', 'date', ''), ('probationMonths', 'int', ''), ('status', 'enum', 'active | probation | noticePeriod | inactive | terminated'), ('statusReason', 'string', ''), ('lastWorkingDay', 'date?', ''), ('branchId', 'string', ''), ('workLocation', 'string', ''), ('managerId', 'string?', 'Employee id'), ('shift', 'string', 'Branch shift name'), ('weeklyOff', 'int?', '1 = Mon … 7 = Sun; personal override'), ('accountStatus', 'enum', 'signedIn | invited | inviteExpired | noAccount'), ('role', 'enum SystemRole', ''), ('invitedAt / lastSignInAt', 'datetime?', ''), ('customValues', 'object', 'key → value'), ('hasAttendance', 'bool', ''), ('activity', 'EmployeeActivity[]', '{text, kind, by, at}'), ('version', 'int', '')]),
    ('EmployeeFieldSettings', [('rules', 'object', 'field → required | optional | hidden; only changed fields. Fields: displayName, workEmail, mobile, personalEmail, dateOfBirth, emergencyContact, designation, department, probation, workLocation, weeklyOff (others locked)'), ('updatedAt / updatedBy', 'datetime / string', ''), ('version', 'int', '')]),
    ('CustomField', [('id, key', 'string', 'key unique'), ('label, description', 'string', ''), ('type', 'enum', 'shortText | longText | number | date | singleSelect | multiSelect | yesNo | url'), ('options', 'string[]', 'For selects'), ('required, sensitive, archived', 'bool', ''), ('departments, branchIds', 'string[]', 'Empty = all'), ('access', 'object', 'audience (hrAdmin | branchManager | attendanceManager | self) → {view, edit}'), ('createdAt', 'datetime?', '')]),
    ('ImportRecord', [('id', 'string', ''), ('fileName', 'string', ''), ('finishedAt', 'datetime', ''), ('by', 'string', ''), ('created, updated, skipped, failed', 'int', ''), ('branchIds', 'string[]', ''), ('invitationsSent', 'int', ''), ('notImported', 'NotImportedRow[]', '{rowNumber, name, code, email, outcome: created|updated|skipped|failed, reason}'), ('createdEmployeeIds', 'string[]', '')]),
    ('Punch', [('id', 'string', ''), ('employeeId', 'string', ''), ('at', 'datetime', 'Server UTC'), ('kind', 'enum', 'punchIn | punchOut | breakStart | breakEnd'), ('source', 'enum', 'app | kiosk | web | correction'), ('correctionId', 'string?', ''), ('replaces', 'string?', 'Punch id')]),
    ('Correction', [('id', 'string', ''), ('employeeId', 'string', ''), ('workDate', 'date', ''), ('changes', 'array', '{kind, at, replaces?}'), ('reason', 'string', ''), ('by / byEmployeeId', 'string', ''), ('createdAt', 'datetime', ''), ('status', 'enum', 'pending | approved | rejected'), ('approverNote', 'string', ''), ('decidedBy / decidedAt', 'string? / datetime?', ''), ('requestId', 'string?', 'CorrectionRequest answered')]),
    ('CorrectionRequest', [('id', 'string', ''), ('employeeId', 'string', ''), ('workDate', 'date', ''), ('kind', 'enum PunchKind', ''), ('proposedAt', 'datetime', ''), ('message', 'string', ''), ('createdAt', 'datetime', ''), ('status', 'enum', 'open | resolved | rejected'), ('rejectReason', 'string', '')]),
    ('DayRecord (calculated)', [('employeeId', 'string', ''), ('date', 'date', ''), ('status', 'enum', 'present | late | leftEarly | halfDay | shortShift | missingPunch | absent | onLeave | holiday | weeklyOff | working | notYet | upcoming | none'), ('sessions', 'array', '{in, out, breaks[]}'), ('shift', 'object?', '{start, end}'), ('workedMinutes, breakMinutes, lateMinutes, earlyMinutes', 'int', ''), ('scheduled', 'bool', ''), ('holidayName', 'string?', ''), ('corrected', 'bool', ''), ('pendingCorrection', 'Correction?', ''), ('correctedBy / correctionReason', 'string?', '')]),
    ('FaceCheck (on Punch.face)', [('result', 'enum', 'verified | notMatched | noFace | notEnrolled'), ('score', 'number?', 'Similarity 0–1'), ('photoUrl', 'string?', 'Signed URL, reviewers and the employee only'), ('review', 'FaceReview?', '')]),
    ('FaceReview', [('punchId', 'string', ''), ('accepted', 'bool', ''), ('by', 'string', ''), ('at', 'datetime', ''), ('note', 'string', 'Required when not accepted')]),
    ('FaceProfile', [('employeeId', 'string', ''), ('status', 'enum', 'pending | approved | rejected'), ('photoUrls', 'string[3]', 'Straight, left, right'), ('consentAt', 'datetime', ''), ('submittedAt', 'datetime', ''), ('decidedBy / decidedAt', 'string? / datetime?', ''), ('rejectReason', 'string', '')]),
    ('FaceExemption', [('employeeId', 'string', ''), ('reason', 'string', ''), ('by', 'string', ''), ('at', 'datetime', '')]),
    ('LeaveType', [('key', 'string', 'e.g. casual'), ('name', 'string', ''), ('color', 'int', 'ARGB'), ('paid', 'bool', ''), ('method', 'enum', 'upfront | monthly | none'), ('allowance', 'number', 'Days per year'), ('startsAfterMonths', 'int', ''), ('carryForwardMax', 'number', ''), ('minDays / maxDays', 'number', ''), ('allowHalfDays, countWeeklyOffs, countHolidays', 'bool', ''), ('noticeDays, backdateDays', 'int', 'backdate ≤ 30'), ('eligibleTypes', 'enum[]', 'Employment types'), ('branchIds, departments', 'string[]', 'Empty = all'), ('active', 'bool', ''), ('optionalHolidaysOnly', 'bool', '')]),
    ('LeavePolicy', [('routes', 'ApprovalRoute[]', '{id, branchId?, typeKey?, second: none|hrIfDays|branchManagerIfDays|hrAlways, minDays}'), ('backdatedSickDays', 'int', ''), ('longestRequestDays', 'int', ''), ('blackouts', 'Blackout[]', '{name, from, to, departments[], branchIds[], blockedTypes[]}'), ('allowNegative', 'bool', ''), ('negativeLimit', 'number', ''), ('cancelApprovedNotStarted', 'bool', ''), ('optionalHolidaysPerYear', 'int', 'Default 1'), ('updatedAt / updatedBy', '', ''), ('version', 'int', '')]),
    ('LeaveRequest', [('id', 'string', 'e.g. L-2514'), ('employeeId', 'string', ''), ('typeKey', 'string', ''), ('from / to', 'date', ''), ('half', 'enum', 'full | first | second'), ('days', 'number', 'Calculated'), ('reason', 'string', ''), ('createdAt', 'datetime', ''), ('status', 'enum', 'pending | changesRequested | approved | rejected | withdrawn | cancelled'), ('steps', 'ApprovalStep[]', '{kind: manager|branchManager|hr, approverId?, note, decidedBy?, decidedAt?, approved?}'), ('history', 'array', '{at, text, by}'), ('decisionNote', 'string', ''), ('amendedFrom', 'object?', '{from, to}')]),
    ('LeaveAdjustment', [('id', 'string', ''), ('employeeId', 'string', ''), ('typeKey', 'string', ''), ('days', 'number', '+ or −'), ('effective', 'date', ''), ('reason', 'string', 'Required'), ('by', 'string', ''), ('carry', 'bool', 'Carried from last year')]),
    ('LeaveBalance (calculated)', [('typeKey', 'string', ''), ('granted, carried, adjusted, used, pending, available', 'number', ''), ('offered', 'bool', 'Type applies to this person')]),
    ('CompanyHoliday', [('id', 'string', ''), ('name', 'string', ''), ('date / endDate', 'date', 'Range ≤ 14 days'), ('category', 'enum', 'festival | national | regional | company'), ('branchIds', 'string[]', 'Empty = all'), ('optional', 'bool', ''), ('description', 'string', ''), ('createdBy', 'string', '')]),
    ('ScheduleAssignment', [('id', 'string', ''), ('level', 'enum', 'employee | group | branch | organization'), ('name', 'string', ''), ('effectiveFrom', 'date', 'Not in the past'), ('branchId', 'string?', ''), ('employeeIds', 'string[]', ''), ('shift', 'string?', ''), ('weeklyOff', 'int?', '')]),
    ('RoleDefinition', [('id', 'string', ''), ('name, description', 'string', ''), ('kind', 'enum', 'system | custom'), ('base', 'enum SystemRole', '"Works like"'), ('scope', 'enum DataScope', ''), ('grants', 'string[]', '"module.action" keys'), ('active', 'bool', ''), ('updatedAt / updatedBy', '', ''), ('version', 'int', '')]),
    ('RoleAssignment', [('key', 'string', 'Employee code or member key'), ('roleId', 'string', ''), ('branchIds', 'string[]', ''), ('teamSize', 'int', 'Calculated'), ('changedAt / changedBy', '', '')]),
    ('SecuritySettings', [('twoStep', 'enum', 'optional | admins | everyone'), ('minPasswordLength', 'int', '8–64, default 10'), ('lockAfterAttempts', 'int', ''), ('lockMinutes', 'int', 'Default 15'), ('adminIdleMinutes', 'int', 'Default 30'), ('employeeIdleDays', 'int', 'Default 30'), ('inviteDays', 'int', 'Default 7'), ('resetMinutes', 'int', 'Default 30')]),
    ('DataSettings', [('exportRights', 'object', 'role → [people | attendance | leave | restricted]'), ('dateFormat', 'enum', 'dmy | iso'), ('durations', 'enum', 'hoursMinutes | decimal'), ('csvSeparator', 'string', ''), ('linkDays', 'int', 'Download link life'), ('punchYears', 'int', 'Retention'), ('leaverYears', 'int', 'Default 3'), ('exportFileDays', 'int', 'Default 30')]),
    ('BrandingSettings', [('color', 'int', ''), ('language', 'string', ''), ('longDates, clock24, indianNumbers, weekStartsMonday', 'bool', '')]),
    ('AppNotification', [('id', 'string', ''), ('recipient', 'string', 'Member key'), ('category', 'enum', 'approvals | attendance | people | system'), ('tone', 'enum', 'ok | fix | no | info | user'), ('title, short, body', 'string', ''), ('facts', 'array', '[label, value] pairs'), ('at', 'datetime', ''), ('route', 'string?', 'App page to open'), ('cta', 'string', 'Button label'), ('read', 'bool', ''), ('event', 'enum NotifyEvent?', '')]),
    ('NotificationPrefs', [('overrides', 'array', '{event, to: employee|manager|hr, channel: inApp|email, on}'), ('digest', 'bool', ''), ('digestAt', 'int', 'Hour'), ('updatedAt', 'datetime?', '')]),
    ('AuditEvent', [('id', 'string', ''), ('at', 'datetime', ''), ('actorName, actorRole', 'string', ''), ('action', 'string', 'e.g. employee.updated'), ('entityType, entityId, entityLabel, entityRoute', 'string', ''), ('branchId', 'string?', ''), ('scopeLabel', 'string', ''), ('summary, reason', 'string', ''), ('source', 'enum', 'web | import | system | kiosk'), ('ip', 'string', 'Masked'), ('changes', 'array', '{field, before, after}'), ('affected, relatedIds', 'string[]', ''), ('previousHash, hash', 'string', 'Chain')]),
    ('OrgStats (platform)', [('id, name, industry, city, state, sizeRange', 'string', 'Organization business details only'), ('createdAt', 'datetime', ''), ('employees, inactiveEmployees', 'int', ''), ('accountsSignedIn, accountsInvited', 'int', ''), ('activeToday', 'int', 'People with a punch today'), ('dailyActive', 'int[30]', 'Oldest first'), ('punches30, leaveRequests30, leavePending', 'int', ''), ('customFields, imports, faceEnrolled, selfieBranches', 'int', 'Feature use'), ('lastActivity', 'datetime?', ''), ('status', 'enum', 'active | settingUp | quiet'), ('branches', 'BranchStats[]', '{id, name, code, city, active, employees, setupPercent, activeToday, selfieCheck}')]),
    ('ExportRecord', [('id', 'string', ''), ('kind', 'enum ReportKind', ''), ('filters', 'string', 'Human summary'), ('requestedBy / requestedById', 'string', ''), ('at', 'datetime', ''), ('format', 'string', 'csv | xlsx'), ('failed', 'bool', ''), ('downloadUrl', 'string?', 'Expires'), ('branchId', 'string?', '')]),
]

# =====================================================================
# Document
# =====================================================================
total = sum(len(m[2]) for m in MODULES)
req = sum(1 for m in MODULES for r in m[2] if r[6] == 'R')

story += [Spacer(1, 55 * mm),
          Paragraph('Staffline Portal', ParagraphStyle('t', fontName='Plex-Semi', fontSize=30, leading=36, textColor=INK)),
          Spacer(1, 4),
          Paragraph('Backend API specification', ParagraphStyle('s', fontName='Plex', fontSize=14, leading=19, textColor=MUTED)),
          Spacer(1, 14),
          Paragraph(f'{total} endpoints in {len(MODULES)} modules: {req} needed to replace the app\'s demo data layer, '
                    f'{total - req} more for server-side calculation, real data volumes and file generation. '
                    f'Every request and response model with its fields, every permission and business rule the '
                    f'server must enforce, background jobs, and a build order.', body),
          Spacer(1, 30 * mm),
          Paragraph('Version 1.3 · 26 October 2026 · for the backend team', small),
          Paragraph('Derived from the Flutter app: <font name="Mono">lib/features/*/domain/</font> '
                    '(repository interfaces and models) and <font name="Mono">lib/core/permissions/</font>.', small),
          PageBreak()]

P('Contents', h1)
for i, t in enumerate(['How the app talks to the backend', 'Endpoint count by module',
                       'Conventions (URLs, auth, JSON, errors, paging, concurrency)',
                       'Authorization: roles, permissions and data scope',
                       'Endpoints by module (with fields, permission and rules)',
                       'Data models', 'Background jobs and server-side events',
                       'Build order and integration checklist', 'Decisions the backend team must make'], 1):
    P(f'{i}.  {t}')
story.append(PageBreak())

# 1
P('1. How the app talks to the backend', h1)
P('The Flutter app never calls HTTP directly from screens. Each feature has a '
  '<b>repository interface</b> in <font name="Mono">lib/features/&lt;feature&gt;/domain/</font>. '
  'Today each one is implemented by an in-memory <font name="Mono">Demo…Repository</font>. '
  'To connect the backend, the mobile/web developer writes an HTTP implementation of the same '
  'interface; no screen changes. This document therefore lists, for every endpoint, which '
  'repository method it <b>replaces</b>.')
table([['Interface (app)', 'Methods', 'Module in this document'],
       ['AuthRepository', '14', 'Authentication and session'],
       ['OrganizationRepository', '11', 'Organization and branches'],
       ['EmployeeRepository', '13', 'Employees, custom fields and import'],
       ['AttendanceRepository', '12', 'Attendance'],
       ['LeaveRepository', '10', 'Leave'],
       ['CalendarRepository', '6', 'Holidays and schedules'],
       ['AccessRepository', '4', 'Roles and access'],
       ['SettingsRepository', '2', 'Settings'],
       ['NotificationRepository', '7', 'Notifications'],
       ['AuditRepository', '2', 'Audit log'],
       ['ReportRepository', '2', 'Reports, exports and dashboards'],
       ['PlatformRepository', '1', 'Platform statistics (super admin)']],
      [W * .35, W * .15, W * .5],
      [ParagraphStyle('m', parent=mono), small, small])
P('<b>Important — the server is the security boundary.</b> The app hides pages and buttons a '
  'role may not use, but that is only for usability. Every endpoint must check the caller\'s '
  'permission, data scope and the business rules in this document, and must never trust IDs, '
  'roles, times or totals sent by the client.')
P('<b>Where the app calculates today.</b> Leave balances and routing (<font name="Mono">LeaveBook</font>), '
  'attendance day status (<font name="Mono">AttendanceBook</font>), dashboards, reports and import '
  'validation run inside the app on fully loaded data. Endpoints marked <b>N</b> move that work to '
  'the server; they are needed once an organization has more than a few hundred people, and they '
  'are the only way to make the rules tamper-proof.')

# 2
P('2. Endpoint count by module', h1)
rows = [['Module', 'Required (R)', 'Server-side (N)', 'Total']]
for name, _, eps, _ in MODULES:
    r = sum(1 for e in eps if e[6] == 'R')
    rows.append([name, str(r), str(len(eps) - r), str(len(eps))])
rows.append(['<b>Total</b>', f'<b>{req}</b>', f'<b>{total - req}</b>', f'<b>{total}</b>'])
table(rows, [W * .55, W * .15, W * .15, W * .15])
P('<b>By HTTP method:</b> ' + ', '.join(
    f'{m} {sum(1 for x in MODULES for e in x[2] if e[0] == m)}'
    for m in ['GET', 'POST', 'PUT', 'PATCH', 'DELETE']) + '.')
P('<b>R</b> = needed to replace the demo repositories one-for-one. <b>N</b> = recommended so the '
  'server calculates (balances, day status, reports, dashboards, import checks) and files are '
  'generated server-side.', small)

# 3
story.append(PageBreak())
P('3. Conventions', h1)
table([['Topic', 'Rule'],
       ['Base URL', '<font name="Mono">https://api.&lt;domain&gt;/api/v1</font>. Everything inside an organization is under <font name="Mono">/orgs/{orgId}</font>; the server checks the caller is an active member of that organization.'],
       ['Format', 'JSON, UTF-8, field names in camelCase exactly as in the data models. Enums are sent as the lower-camel names listed (e.g. <font name="Mono">noticePeriod</font>).'],
       ['Dates and times', 'Instants: ISO 8601 UTC (<font name="Mono">2026-10-14T08:40:00Z</font>). Calendar dates: <font name="Mono">YYYY-MM-DD</font>. Times of day: minutes after midnight (int). Time zones: IANA ids. The server converts to the branch time zone when grouping work days.'],
       ['Authentication', 'Access token (JWT, 15 min) in <font name="Mono">Authorization: Bearer</font>. Refresh token in an httpOnly, Secure, SameSite=Strict cookie (web) or secure storage (mobile), rotated on each refresh. "Keep me signed in" extends the refresh lifetime.'],
       ['Re-authentication', 'Saving roles and security settings requires <font name="Mono">X-Reauth: &lt;token&gt;</font> from <font name="Mono">POST /auth/reauthenticate</font> (valid 5 minutes). Logged in the audit log.'],
       ['Paging', 'List endpoints take <font name="Mono">page</font> (1-based) and <font name="Mono">pageSize</font> (default 50, max 200) or <font name="Mono">cursor</font>; response <font name="Mono">{items, total, page, pageSize}</font> or <font name="Mono">{items, nextCursor}</font>.'],
       ['Concurrency', 'Editable records carry <font name="Mono">version</font>. Send it back on PUT (or <font name="Mono">If-Match</font>). A stale version → <b>409 conflict</b>; nothing is overwritten.'],
       ['Idempotency', '<font name="Mono">Idempotency-Key</font> header on punches, imports, exports and invitations. A repeat with the same key returns the first result.'],
       ['Reasons', 'Mutations that the app asks a reason for (status changes, adjustments, role changes, reveals, corrections) carry <font name="Mono">reason</font>; it is stored in the audit entry.'],
       ['Masking', 'Restricted fields (mobile, personal email, date of birth, registration number, IP) are returned masked (e.g. <font name="Mono">98••••••21</font>) unless the caller has the restricted right and organization scope.'],
       ['Rate limits', 'Sign-in, two-step, forgot-password and resend endpoints: per IP and per account. 429 with <font name="Mono">Retry-After</font>.']],
      [W * .2, W * .8])
P('Error format', h3)
codeblock('''HTTP 422
{
  "error": {
    "code": "validation",          // see table
    "message": "Check the highlighted fields.",   // safe to show
    "fieldErrors": { "workEmail": "This email belongs to Komal Desai (EMP-0231).",
                     "custom.bloodGroup": "Choose a value." },
    "until": null,                 // set for "locked"
    "reference": "req_8a234"       // support id, always set
  }
}''')
table([['HTTP', 'code', 'App Failure class', 'When'],
       ['400 / 422', 'validation', 'ValidationFailure (fieldErrors)', 'Input rejected; field keys match model field names'],
       ['401', 'unauthenticated', '(sign-out)', 'Missing or expired token'],
       ['403', 'forbidden', 'PermissionFailure', 'Permission, scope or self-approval rule'],
       ['404', 'notFound', 'NotFoundFailure', 'Missing <b>or out of the caller\'s scope</b> (never reveal it exists)'],
       ['409', 'conflict', 'ConflictFailure', 'Stale version, duplicate, rule conflict (e.g. branch still has employees)'],
       ['410', 'expired', 'ExpiredFailure', 'Reset link, invitation or code expired or used'],
       ['423', 'locked', 'LockedFailure (until)', 'Too many attempts'],
       ['429', 'rateLimited', 'NetworkFailure', 'Rate limit'],
       ['5xx', 'unexpected', 'UnexpectedFailure (reference)', 'Server error; include reference']],
      [W * .1, W * .14, W * .3, W * .46])

# 4
story.append(PageBreak())
P('4. Authorization: roles, permissions and data scope', h1)
P('A permission is a key <font name="Mono">module.action</font>. Modules: <font name="Mono">organization, employees, employeeFields, '
  'attendance, leave, holidays, settings, roles, reports, importExport, auditLog</font>. Actions: '
  '<font name="Mono">view, create, edit, deactivate, approve, correct, export</font>. Each role has a set of '
  'grants and one data scope. Custom roles store their own grants and a base system role.')
table([['Module', 'Owner', 'HR Admin', 'Branch Mgr', 'Attendance Mgr', 'Leave Approver', 'Employee'],
       ['organization', 'all', 'view', 'view', '—', '—', '—'],
       ['employees', 'all', 'all', 'view create edit export', '—', '—', '—'],
       ['employeeFields', 'all', 'view edit', '—', '—', '—', '—'],
       ['attendance', 'all', 'all', 'view approve correct export', 'view approve correct export', '—', '—'],
       ['leave', 'all', 'all', 'view create approve export', '—', 'view approve', '—'],
       ['holidays', 'all', 'all', 'view', '—', '—', '—'],
       ['settings', 'all', 'view edit', '—', '—', '—', '—'],
       ['roles', 'all', '—', '—', '—', '—', '—'],
       ['reports', 'all', 'view export', 'view export', '—', '—', '—'],
       ['importExport', 'all', 'all', '—', '—', '—', '—'],
       ['auditLog', 'all', 'view export', '—', '—', '—', '—']],
      [W * .16] + [W * .14] * 6)
table([['Data scope', 'Roles', 'Server filter on every read, write and export'],
       ['organization', 'Owner, HR Admin', 'All records of the organization'],
       ['assignedBranches', 'Branch Manager, Attendance Manager', '<font name="Mono">record.branchId ∈ member.branchIds</font> (branches list too)'],
       ['ownTeam', 'Leave Approver', 'Employees whose <font name="Mono">managerId</font> = the member\'s employee id'],
       ['ownRecords', 'Employee', 'Only the member\'s own employee record']],
      [W * .2, W * .3, W * .5])
P('Rules every endpoint applies', h3)
bullets([
    '<b>Self-service</b> (punch, own attendance, own leave, own profile, own notifications) is allowed for every member with an employee record, whatever the role.',
    '<b>Owner-only:</b> organization edit, owner profile, branch create/edit/status/setup, roles (all), security and data settings, revealing masked values. Owner-only grants can never be given to another role; the last owner cannot lose the role.',
    '<b>No self-approval:</b> nobody decides their own leave request or attendance correction.',
    '<b>Out of scope = 404</b>, not 403, so the server never confirms a record exists.',
    '<b>Every mutation</b> writes an audit entry (section 7) in the same transaction.',
    'Role or permission changes apply on the member\'s next request: keep grants server-side (or short-lived tokens) and invalidate on change.',
])

# 5
for idx, (name, intro, eps, rules) in enumerate(MODULES, 1):
    story.append(PageBreak() if idx == 1 else Spacer(1, 8))
    if idx == 1:
        P('5. Endpoints by module', h1)
        P('Paths are relative to <font name="Mono">/api/v1</font>; <font name="Mono">~</font> stands for '
          '<font name="Mono">/orgs/{orgId}</font>. <b>Replaces</b> = the app\'s repository '
          'method. <b>R/N</b>: see section 2. Field names refer to section 6.', small)
    P(f'5.{idx} {name} ({len(eps)})', h2)
    P(intro, small)
    story.append(Spacer(1, 3))
    rows = [['#', 'Method', 'Path', 'Permission', 'Input', 'Output', 'Replaces', '']]
    extra = []
    for n, (m, path, perm, inp, out, repl, kind) in enumerate(eps, 1):
        rows.append([str(n), f'<font name="Mono-Medium" color="{METHOD[m]}">{m}</font>',
                     path.replace(O, '~'),
                     perm, inp, out, repl, kind])
    table(rows, [W * .035, W * .07, W * .19, W * .17, W * .2, W * .16, W * .145, W * .03],
          [small, small, mono, small, small, small, mono, small])
    P('Rules the server must enforce', h3)
    bullets(rules)

# 6
story.append(PageBreak())
P('6. Data models', h1)
P('Types: <font name="Mono">string, int, number</font> (decimal), <font name="Mono">bool, date</font> (YYYY-MM-DD), '
  '<font name="Mono">datetime</font> (ISO 8601 UTC), <font name="Mono">enum</font>, <font name="Mono">[]</font> '
  'array, <font name="Mono">?</font> nullable. Shared enums: <b>SystemRole</b> = owner | hrAdmin | branchManager | '
  'attendanceManager | leaveApprover | employee. <b>DataScope</b> = organization | assignedBranches | ownTeam | ownRecords. '
  '<b>NotifyEvent</b> = leaveSubmitted | leaveDecided | leaveWithdrawn | missingPunch | correctionDecided | '
  'repeatedLateness | faceFlagged | faceEnrolSubmitted | faceDecided | invitation | profileChanged | inviteBounced | holidaySoon | holidayAdded. '
  '<b>ReportKind</b> = roster | changes | daily | monthly | missing | balances | requests | holidays | audit.', small)
story.append(Spacer(1, 4))
for name, fields in MODELS:
    rows = [['Field', 'Type', 'Notes']] + [[f'<font name="Mono">{f}</font>', t, n] for f, t, n in fields]
    data_rows = rows
    P(name, h3)
    table(data_rows, [W * .34, W * .2, W * .46])

# 7
story.append(PageBreak())
P('7. Background jobs and server-side events', h1)
table([['Job / event', 'When', 'What it does'],
       ['Audit writer', 'Every mutation (same transaction)', 'Appends a sealed AuditEvent: actor, action, entity, before/after, reason, scope, source, masked IP, previousHash → hash.'],
       ['Notification fan-out', 'After leave, attendance, invitation, profile and holiday events', 'Creates in-app notifications and queues emails per the preference matrix; skips the actor.'],
       ['Email sender', 'Queue worker', 'Verification codes, invitations, password resets, notifications, digest. Records bounces (shown in Invitations as "Not delivered").'],
       ['Leave accrual', '1st of each month', 'Monthly accrual after the waiting months; or compute on read from rules (preferred: no stored balance).'],
       ['Year-end carry-forward', '1 January (leave year Jan–Dec)', 'Carries up to <font name="Mono">carryForwardMax</font>, lapses the rest; writes adjustments with <font name="Mono">carry = true</font>.'],
       ['Missing-punch detection', 'After each shift end (branch time zone)', 'Flags open sessions; sends reminders if enabled; marks > 3 days as overdue.'],
       ['Daily digest', 'Organization <font name="Mono">digestAt</font> hour', 'Summary email for managers/HR if digest is on.'],
       ['Invitation expiry', 'Hourly', 'Sets <font name="Mono">accountStatus = inviteExpired</font> after <font name="Mono">inviteDays</font>.'],
       ['Export files', 'On request; cleanup daily', 'Generates CSV/XLSX in the background; deletes files after <font name="Mono">exportFileDays</font>; links expire after <font name="Mono">linkDays</font>.'],
       ['Retention', 'Daily', 'Removes punch data older than <font name="Mono">punchYears</font> and leavers older than <font name="Mono">leaverYears</font> (keeping audit entries).'],
       ['Holiday reminders', 'Daily', '"Holiday next week" notifications per branch.'],
       ['Selfie clean-up', 'Daily', 'Deletes punch selfies older than 90 days; deletes face data of people who left.']],
      [W * .2, W * .25, W * .55])

# 8
P('8. Build order and integration checklist', h1)
table([['Phase', 'Build', 'App screens that start working'],
       ['1', 'Auth & session, uploads, organization, branches, settings (read)', 'Sign-in, two-step, register, onboarding, organization and branch setup'],
       ['2', 'Employees, custom fields, invitations, import', 'Directory, profiles, add/edit, import wizard, invitations'],
       ['3', 'Attendance (punch, corrections, requests) + day calculation', 'Employee home, my attendance, attendance pages'],
       ['4', 'Holidays & schedules, leave (types, policy, requests, decisions, balances)', 'Leave and holiday pages, approvals'],
       ['5', 'Roles, audit log, notifications, settings (write)', 'Roles & permissions, audit, notifications, settings'],
       ['6', 'Reports, exports, dashboards, background jobs', 'Overview, branch dashboard, reports, export history']],
      [W * .08, W * .5, W * .42])
bullets([
    'For each module, the app developer replaces <font name="Mono">Demo…Repository</font> with an HTTP version of the same interface and runs the existing 663 tests plus <font name="Mono">integration_test/</font> against a seeded test server.',
    'Seed the test server with the demo organization (Meridian Textiles, 4 branches, 248 employees, six demo accounts) so the QA rule book (<font name="Mono">docs/qa/Staffline_Rule_Book_QA.pdf</font>) applies unchanged.',
    'Contract tests: every endpoint has a test for its permission (allowed and refused role), its scope (out-of-scope record returns 404) and each validation message.',
    'Build the production app with <font name="Mono">--dart-define=SHOW_DEV_TOOLS=false</font>.',
])

# 9
P('9. Decisions the backend team must make', h1)
table([['Topic', 'Notes'],
       ['Stack and database', 'Any stack; a relational database (PostgreSQL) fits: organization-scoped tables, row-level security per organization recommended.'],
       ['Email provider', 'Transactional email with bounce webhooks (feeds "Not delivered" invitations).'],
       ['File storage', 'Object storage with signed URLs; malware scan on upload.'],
       ['Two-step', 'TOTP (RFC 6238) with 10 backup codes; trusted-device cookie 30 days.'],
       ['Time', 'Server clock in UTC; IANA time-zone database kept up to date.'],
       ['Audit hash', 'SHA-256 chain per organization (the demo uses FNV-64).'],
       ['Platform administration', 'Statistics endpoints are listed (5.12). Support sessions, billing and suspend from boards S97–S98 are not approved.'],
       ['Kiosk punching, location checks', 'Not designed yet; <font name="Mono">source = kiosk</font> is reserved.'],
       ['Face matching service', 'Choose a face recognition engine with liveness detection (self-hosted model or a cloud API that keeps data in India), and set the match threshold from a pilot. Biometric data needs a DPDP-compliant consent record and a data-protection impact assessment.']],
      [W * .25, W * .75])


def page(c, doc):
    if doc.page == 1:
        return
    c.saveState()
    c.setFont('Plex', 7.5)
    c.setFillColor(MUTED)
    c.drawString(16 * mm, 10 * mm, 'Staffline Portal · Backend API specification · v1.3')
    c.drawRightString(A4[0] - 16 * mm, 10 * mm, f'Page {doc.page}')
    c.restoreState()


SimpleDocTemplate(OUT, pagesize=A4, leftMargin=16 * mm, rightMargin=16 * mm,
                  topMargin=15 * mm, bottomMargin=17 * mm,
                  title='Staffline Portal — Backend API specification',
                  author='Staffline project').build(story, onFirstPage=page, onLaterPages=page)
print('ok', OUT, total, req)
