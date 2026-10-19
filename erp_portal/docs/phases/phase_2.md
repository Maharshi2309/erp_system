# Phase 2 — Authentication and application shell

Status: **Complete, awaiting approval** · 16 Oct 2026

## Delivered

| Screen | Route | Notes |
|---|---|---|
| S03 Welcome & sign-in | `/welcome` | Generic error; keep me signed in; demo-accounts box (demo builds) |
| S04 Owner registration | `/register` | Live password rules; error summary; server errors on the field |
| S05 Email verification | `/verify-email` | 6-digit code; 45 s resend timer; "Email verified" state |
| S06 Two-step sign-in | `/sign-in/verify` | Authenticator or backup code; 30-day trusted device; locks after 3 wrong codes for 15 min |
| S07 Forgot password | `/forgot-password` | Request state + "sent" state; never reveals whether an account exists |
| S08 Reset password | `/reset-password?token=` | Rules, mismatch error, expired-link state |
| S09 Invitation | `/invite?token=` | Inviter banner, read-only details, own password; expired/missing token state |
| S10 Organization selection | `/choose-organization` | Last used; deactivated shown but not selectable; also used to switch |
| S72 Access denied | `/access-denied?from=` | Inside the member's own shell; "Ask the owner for access" |
| Role-aware shell | — | Per-role menus; account menu (switch organization, sign out, my profile); employee/approver bottom tabs on phones |
| Session restore | `/loading` | "Keep me signed in" survives reload (browser storage, IDs only) |

Demo accounts (password `Staffline@2026`, code `482913`, backup `7KQ2-M9XD`): Ankit (owner, 3 organizations), Hetal (HR admin), Jignesh (branch manager), Mitesh (attendance manager), Aarav (leave approver), `EMP-0229` Isha (employee). Demo links: invitation `demo-invite`, reset `demo-reset`.

## Deviations from the design
- Mobile number on S04 is one field labelled "(+91)" instead of a country-code select. Only India is in scope (D-03).
- The two-step success card is skipped (D-16).
- S07's initial request state is not drawn in the design; it reuses the same card with "Send reset link" (Q-12).
- After email verification, onboarding opens as a "Not built yet — Phase 3" page with a Sign out button.

## Verification (16 Oct 2026)

| Check | Result |
|---|---|
| Format check | 0 files changed |
| `flutter analyze` | No issues |
| `flutter test` | 215 passed, 0 failed |
| Line coverage | 94.9% (2508 / 2644) |
| `flutter build web --release` | Built |
| Responsive | Sign-in pages at 320 / 390 / 1440 px and 200% text; shell matrix (11 sizes) |
| Screenshots | 16 images in `test_screenshots/output/` |

Bugs found by the tests and fixed:
- "Ask the owner for access" crashed: the controller read a provider that depends on itself.
- Welcome brand pane overflowed on short desktop screens; it now scrolls.
- Register top bar overflowed at 320 px; it now wraps.
- A test helper reused one provider container across pumps; each pump now gets a fresh one.

## Known limitations
- **Not secure.** Demo repository, plain-text demo passwords, no server checks (D-01). All of this is replaced when a backend is chosen.
- Account details reset on reload, except what "Keep me signed in" stores.
- "Ask the owner for access" only shows a confirmation; the owner gets no notification until Phase 7.
- Platform super-admin sign-in is not included (Q-13).
