# Open Questions

Decisions needed before or during implementation. Each lists the options, my recommendation, and the first phase it blocks. **Blocking** = I cannot start that phase responsibly without an answer.

Status key: Open · Answered (record answer and date here when decided).

---

## Blocking Phase 1

### Q-01 · Backend — Open
No backend exists and none is specified. Auth, tenant isolation and authorization must be server-side (PRD §11, §16). The choice changes the data layer, auth flow and what "verified" can mean in every later phase.

| Option | Notes |
|---|---|
| A. Firebase (Auth + Firestore + Cloud Functions) | Fast to start; MFA, email links available; multi-tenant rules and reports need care; Firestore queries are limited for reporting |
| B. Supabase (Postgres + Auth + row-level security) | Relational model fits the PRD data model and reports; RLS gives tenant/branch scoping; MFA supported |
| C. Your own REST/GraphQL API | Full control; needs a separate backend project and team |
| D. Build the Flutter app against repository interfaces with a clearly labelled in-memory "demo" implementation now, and choose the backend later | Lets Phases 1–3 proceed; nothing is production-secure until a backend lands |

**Recommendation:** decide now if possible (B suits the relational, report-heavy PRD). Otherwise D, with the backend chosen before Phase 5.

### Q-02 · Target platforms — Open
The design is a web portal (desktop 1440, tablet 768) plus employee screens drawn for phones (390). The Flutter project has all six platforms scaffolded.

Options: A. Flutter **Web** first, responsive down to 320 px · B. Web + Android/iOS apps (employees punch from the native app) · C. All platforms.

**Recommendation:** A for Phases 1–7, with Android/iOS builds checked in Phase 8 if you want employee apps (PRD §22 suggests responsive web first). Desktop (macOS/Windows/Linux) folders can be left untouched.

### Q-03 · Employee self-service at tablet/desktop widths — Open
Self-service screens exist only at 390 px. An employee or approver opening the portal on a laptop needs a layout.

Options: A. Centre the phone layout in a max-width column (≈ 480 px) with the bottom tabs · B. Give employees the admin-style sidebar shell at ≥ 768 px using the same cards · C. Design new desktop screens first.

**Recommendation:** B — reuse the shell and existing cards; no new visual language. Note the Leave Approver home (S34) already shows employee "ME" items in a desktop sidebar, which supports B.

---

## Blocking Phase 2

### Q-04 · Admin sidebar per role — Open (discrepancy D1)
Boards disagree on the admin menu. **Recommendation:** permission-driven menu — show an item only if the role has `view` on that module. Owner gets all 11 items + Notifications.

### Q-05 · One shell for onboarding and the app — Open (D2)
**Recommendation:** single shell; show the per-branch progress list in the sidebar while any branch is below 100 %, as in the onboarding prototype.

### Q-06 · Sign-in identifiers and account provisioning — Open
Design: work email **or** employee ID + password (S03); owners self-register (S04); employees only by invitation (S09). Phone sign-in is not designed.
**Recommendation:** confirm exactly that: email or employee ID; no employee self-registration; invites only.

### Q-08 · Two-step verification scope — Open
S06 says two-step is required for admin roles; S83 offers Optional / Admins / Everyone (default: admins).
**Recommendation:** default "Required for anyone with admin access", configurable by the owner. Requires backend TOTP support (Q-01).

---

## Blocking Phase 3

### Q-07 · Time zones in onboarding — Open (most important PRD gap)
PRD: organization default time zone and branch time zone are **required** IANA ids. Onboarding v2 collects neither; the branch form only asks for an Indian state. Time zone appears later in Org profile (S35) and full branch edit (S37).

| Option | Effect |
|---|---|
| A. Default the organization to `Asia/Kolkata` (from country India) and let branches inherit it; editable in S35/S37 | Matches the design exactly; correct for India-only customers |
| B. Add a "Time zone" select to the create-organisation and branch forms | Satisfies PRD literally; changes the "3 fields" design |
| C. Infer from browser time zone, confirm on the dashboard | Extra UI |

**Recommendation:** A, if the first release is India-only (PRD §22 "Target market"). Confirm the market.

### Q-18 · Demo data — Open
The design shows Meridian Textiles sample data. **Recommendation:** ship a seeded demo repository (dev flavour only, clearly labelled) with the same sample organisation so every screen can be reviewed before the backend exists; production flavour never shows sample numbers.

---

## Needed by later phases

### Q-09 · Offline punch vs "never show success before server confirms" — Open (Phase 5)
S96 shows an offline punch "Saved on this phone · will sync"; PRD §8.1 and S86 say never show success until the server confirms.
Options: A. No offline punching — show "You're offline" and keep the button disabled · B. Queue offline punches, clearly labelled "not yet confirmed", sync later with the original tap time.
**Recommendation:** A for the first release (web-first); B only with native apps.

### Q-10 · Breaks and kiosk punching — Open (Phase 5)
PRD supports "On break" if break tracking is enabled; the employee home has no break button, but S88 shows break events "from Mobile app". The attendance-rules panel offers "Shared kiosk" with no kiosk screen.
**Recommendation:** breaks recorded from schedule rules only (unpaid break subtracted) — no break button in release 1; hide "Shared kiosk" until designed.

### Q-11 · Leave durations — Open (Phase 6)
Design supports full day, first half, second half. PRD mentions hourly leave optionally. **Recommendation:** no hourly leave in release 1.

### Q-12 · Screens referenced but not designed — Open (Phases 2–7)
List in `screen_inventory.md` (end). Options per item: (a) leave out and hide the trigger, (b) build a minimal version from existing components and show it to you for approval in that phase, (c) design it first.
**Recommendation by item:**

| Item | Phase | Recommendation |
|---|---|---|
| Forgot-password request state | 2 | (b) same card, "Send reset link" |
| Change password, 2-step setup, signed-in devices (My profile) | 2 | (b) |
| "Ask the owner for access" | 2 | (b) sends a notification to the owner |
| Global search results | 4 | (b) dropdown of matching employees/requests |
| Terminate / archive employee | 4 | (b) dialog: effective date + reason |
| Employee correction request form | 5 | (b) bottom sheet: proposed time + reason |
| Corrections list, Attendance exports (attendance-manager nav) | 5 | (b) list reusing S54 rows / link to S73 |
| Leave "Request changes" | 6 | (a) hide until defined, or (b) reason → status "Changes requested" |
| Team calendar (approver) | 6 | (a) hide |
| Leave attachments, restricted reasons | 6 | (a) out of release 1 |
| Email template editor | 7 | (a) hide link |
| Platform: Support access, Plans & billing, Platform audit, System status, read-only workspace | 7 | (a) unless Q-13 says platform admin is in scope |

### Q-13 · Platform super-admin — Answered in part, 24 Oct 2026 (D-75)
**Answer:** a statistics-only super admin (no personal data) is built. Support access, plans & billing, suspend and owner account help remain open.

PRD marks it optional; design has two screens. **Recommendation:** defer to after release 1 unless you operate Staffline as SaaS now.

### Q-14 · Deactivated membership in organization selector — Open (Phase 2)
S10 shows a deactivated membership ("history kept"). Can that user open it read-only? **Recommendation:** shown but not selectable.

### Q-15 · Languages — Open (Phase 7)
S85 offers English (India), Gujarati, Hindi. **Recommendation:** English only in release 1; build with Flutter localization so translations can be added.

### Q-16 · PDF reports — Open (Phase 7)
Design offers XLSX and CSV only. **Recommendation:** XLSX + CSV; no PDF in release 1.

### Q-17 · "Organisation" vs "Organization" spelling — Open (D5)
**Recommendation:** use "Organization" everywhere (majority of screens and the PRD), unless you prefer the exact per-screen copy.

### Q-19 · Product name and app identity — Open (Phase 1)
Design brand is **Staffline**; the Flutter package is `erp_portal`. **Recommendation:** keep the package name, use "Staffline" as the app title and in UI. Confirm logo/brand assets are yours to use.

### Q-20 · Version control — Open (Phase 1)
`ERP System/` is not a git repository. **Recommendation:** initialise git in `erp_portal/` at the start of Phase 1 so each phase is a reviewable commit. I will not commit or push without your instruction.

---

## Answered

| Q | Answer (16 Oct 2026) | Consequence |
|---|---|---|
| Q-01 Backend | No backend integration for now | Option D: every feature talks to repository interfaces; the only implementation is a clearly labelled in-memory **demo** data source with Meridian Textiles sample data. Nothing is production-secure until a backend is added. |
| Q-02 Platforms | As recommended | Flutter Web first, responsive 320–1920 px. Android/iOS checked in Phase 8 if wanted. |
| Q-03 Employee screens on wide screens | As recommended | Employees and approvers get the same sidebar shell at ≥ 768 px, reusing the phone cards. |
| Q-07 Time zones | Default `Asia/Kolkata`, changeable | Organization defaults to `Asia/Kolkata`; branches inherit it; the owner can change the organization time zone and any branch's time zone (IANA ids). |

Questions without an answer follow the recommendation written under each one, unless you say otherwise.
