# Phase 8 — Responsive QA and release readiness

Status: **Complete, awaiting final approval** · 20 Oct 2026

The app is ready as a **demo / pilot web build**. It is **not production-ready** until a backend enforces authentication, authorization and data storage (see "Security limitations" and "Remaining production configuration").

## 1. Test results (20 Oct 2026, final run)

| Check | Result |
|---|---|
| `dart format --output=none --set-exit-if-changed .` | 0 files changed |
| `flutter analyze` | No issues |
| `flutter test` | **649 passed, 0 failed** (65 new since Phase 7) |
| Line coverage | 90.9% (21464 / 23613 lines) |
| `flutter test integration_test -d macos` | **5 passed, 0 failed**: the 10 critical journeys, on a real macOS window |

### Critical journeys (`integration_test/journeys_test.dart`)

| # | Journey | Covered by |
|---|---|---|
| 1 | Owner registration and organization setup | "1–2 owner registers…" |
| 2 | Branch creation | "1–2 owner registers…" |
| 3 | Employee creation (invite sent) | "3 HR adds an employee…" |
| 4 | Employee sign-in through the form | "4–8 employee signs in…" |
| 5 | Punch in / punch out | "4–8 …" |
| 6 | Leave request submission | "4–8 …" |
| 7 | Approver decision | "4–8 …" (approver signs in through the form, two-step code) |
| 8 | Employee sees the new status and balance | "4–8 …" |
| 9 | Role restrictions (menus, guarded URLs, access denied) | "9 role restrictions…" |
| 10 | Reports and authorized exports (allowed and refused) | "10 reports and authorized exports" |

Import of employees is covered by widget tests (Phase 4), not the device journey.

### Responsive and accessibility QA (`test/qa/`)

| Test | What it checks |
|---|---|
| Matrix | Every page for owner, branch manager, leave approver and employee at 320×568, 375×667, 390×844, 430×932, 768×1024, 1024×768, 1280×800, 1440×900 and 1920×1080, and at widths 600, 720, 900, 1100 and 1600. It fails on any layout error (overflow, clipped flex) and if the page is wider than the screen. |
| Text scaling | The same pages at 130% and 200% text, at 390 and 1440 px |
| Resizing | Pages survive the window being resized between 320 and 1440 px |
| Overlays at 320 px | The change-role dialog, the adjust-balance side panel and the role review dialog stay inside the screen |
| Keyboard | Tab order on sign-in (email → password → "Forgot password?"), Enter submits, Escape closes dialogs and side panels, and keyboard focus shows the focus ring |

Charts and tables: charts sit in their card's width; wide tables scroll sideways inside their own box and never widen the page.

### Defects found and fixed in this phase
- **Previous user's page after sign-out.** After one person signed out, the next person to sign in landed on the page the previous person had open, which may be a page they can't use. Sign-out now always returns to the welcome page.
- **Employee and branch forms overflowed at 600–720 px**, a tablet in portrait or a narrow browser window: by 106 px on the right and 209 px at the bottom. The header actions now wrap. The "changes" panel moves under the form below desktop widths.
- **Overflows at 200% text:**
  - the sidebar organization header;
  - the attendance chart axis;
  - the locked "Branch: Surat" chip on the branch dashboard and the employee directory.
- **Large text was squeezed inside buttons.** Buttons had a fixed height. They now grow with the text and keep their designed height at normal size.
- **Avatar initials were cut to one letter at 200% text, and the bell badge covered the avatar.** Both now cap text scaling inside their fixed circles; the bell's tooltip still reads the count.
- **Keyboard order on sign-in.** Tab went from the email field to "Forgot password?" and skipped past the password field. It now goes to the password field first.
- **iOS build failed.** `file_picker` needs iOS 14, so the iOS minimum was raised from 13.0 to 14.0.
- **HR admins couldn't see Organization or Branches.** Answered on 20 Oct 2026: they can now see every branch read-only. Only the owner edits.

## 2. Build results (macOS host)

| Platform | Command | Result |
|---|---|---|
| Web | `flutter build web --release` | ✅ Built `build/web` |
| macOS | `flutter build macos` | ✅ Built `erp_portal.app` (53.7 MB) |
| iOS | `flutter build ios --no-codesign` | ✅ Built `Runner.app` (22.3 MB), unsigned |
| Android | `flutter build apk` | ❌ **Not built.** The Android SDK licences aren't accepted on this machine and Gradle waits on them. Run `flutter doctor --android-licenses` (your decision to accept), then build again. |
| Windows, Linux | — | Not possible on a Mac. They need their own build machines. |
| Web in a browser | `flutter run -d chrome` | ⚠ **Not run.** Chrome isn't installed here, so the journeys ran on macOS (same Flutter engine and layouts). Before go-live, run the integration tests in Chrome. |

## 3. Responsive screenshots

The screenshots are in `test_screenshots/output/` (143 images):
- **`p8/`**: Overview (owner), Employees (owner) and My attendance (employee) at each of the 9 matrix sizes, plus three pages at 200% text.
- **Root folder**: 113 per-screen images from Phases 1–7.

Regenerate them with `flutter test test_screenshots --update-goldens`.

## 4. Known defects

None are known that break a flow. Open cosmetic points:
- At 200% text, long menu labels and narrow filter selects shorten with "…". The full text is in the tooltip and the select's options.
- On phones, a toast can briefly sit over a sticky bottom action bar for its 4 seconds (since Phase 3).

## 5. Security limitations (must be fixed before real data)

- **No backend.** All data is in memory, seeded with demo data, and lost on reload (D-01). Nothing is stored server-side.
- **Demo authentication:**
  - one shared demo password and a fixed two-step code;
  - passwords are not hashed;
  - no rate limiting;
  - "Keep me signed in" uses browser storage.
- **Authorization is client-side only.** Roles, branch scope, owner-only actions and export rights decide what is *shown*. Anyone who changes the client can bypass them. The backend must enforce every rule (D-53, D-59).
- **The audit log** is checksum-chained in memory and is not tamper-proof storage.
- **Settings stored but not enforced:** password minimum length, lockout, idle timeout and session length.
- **Emails are not sent.** Invitations, password resets and notifications go to an in-memory outbox.
- **Time and location are not checked.** Punch times come from the device clock, with no location or kiosk verification.
- **Uploads stay in the browser.** Logo and photo uploads are kept in memory and never scanned.

## 6. Unimplemented or deferred requirements

| Item | Status |
|---|---|
| Platform administration (S97–S98) | Not decided by you; not built (D-62) |
| Backend, real sign-in, email delivery | Not chosen (Q-01) |
| Work schedule templates as free-form edits | Shown, edited through branch hours (D-61) |
| Branding theme and other languages | Saved and previewed; the app stays in its theme and English (D-61) |
| Attendance policy "takes effect on" date, named shared policies, rounding, overtime | Not modelled (Phase 7) |
| Daily digest emails, repeated-lateness alerts | Settings stored only |
| Two-step setup and device list in My profile | Not designed; status only |
| Live recording of failed sign-ins | Seeded only |
| Employee terminate / archive, correction-request form, team calendar, global search results | Not drawn in the design (Q-12) |
| Leave attachments, encashment, carried-days expiry, year-end job | Not built (Phase 6) |
| Break buttons and kiosk mode | Not designed / setting only |
| Drag-and-drop file upload | "Choose file" only |

## 7. Remaining production configuration

1. **Choose and build the backend** (Q-01): auth with hashed passwords, TOTP and rate limits; tenant and branch scoping in the database; append-only audit; email delivery; file storage.
2. **Replace the demo repositories.** Each feature's `data/Demo*Repository` gets a real implementation of the same interface; the screens don't change.
3. **Build with `--dart-define=SHOW_DEV_TOOLS=false`.** This hides the demo-account list, the role switcher and the design gallery.
4. **Web hosting:** HTTPS, a fallback to `index.html` for deep links, security headers (CSP, HSTS), and caching for `main.dart.js`.
5. **App identity:**
   - bundle IDs are still `com.example.erpPortal`;
   - app names and icons;
   - iOS signing team;
   - Android signing key and accepted licences.
6. **Real clock and time zone** come from the server. Default organization zone: Asia/Kolkata.
7. **Monitoring:** error reporting and analytics, both chosen with your privacy policy.
8. **Source control:** the project is not a git repository yet. You said you'll decide when to run `git init`.

## 8. Final folder structure

`lib/` hasn't changed shape since Phase 7. See `docs/architecture.md` ("Folders (final, Phase 8)").
- **Code:** 182 Dart files across `app/`, `core/`, `shared/` and 13 feature folders, each with `domain/`, `data/` and `presentation/` as needed.
- **Tests:**
  - `test/unit`, `test/widget`, `test/qa` (new) and `test/test_helpers`;
  - `integration_test/` (new);
  - `test_screenshots/`.
- **Docs:** `docs/`, with `README.md` at the root.

## 9. Setup and run

See `README.md`: requirements, `flutter pub get`, run on web or macOS, demo accounts, build commands and the full check list.
