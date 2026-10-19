# Screen Inventory

98 screens from the Staffline design canvas, in flow order. IDs (S01–S98) follow the design guide. Board = file under `project/` in the canvas.

Legend
- **Live** = the board has working interactions in the prototype. **Static** = one fixed state is drawn.
- **Confirmed** = read from the board's markup or script. **Unconfirmed** = described only in the guide, or implied by a link that leads nowhere; marked ⚠.
- Width = the frame width the board is drawn at. "Fluid" = drawn as a responsive page (flex/wrap, `max-width`).
- Phase = implementation phase from the master prompt (1 Foundation · 2 Auth & shell · 3 Onboarding & org · 4 Dashboards & employees · 5 Attendance · 6 Leave & holidays · 7 Roles, settings, reports, notifications, audit).

Common to every admin screen (confirmed): left sidebar (logo + org name + role, nav items with count badges, user card at the bottom), top bar (breadcrumb, global search "Search employees, requests…" with `/` hint on the owner dashboard, notification bell with unread count, avatar menu), "Open navigation" button when collapsed. Content capped at 1360 px.

---

## Stage 0 — Reference (designers, developers) · Phase 1

### S01 · Design system — foundations & components — `Main.dc.html` · 1440 · Static
- **Purpose:** tokens and component rules every screen uses (see `reference_audit.md` §4).
- **Contains:** colour tokens, type scale, spacing/radius/elevation, layout tokens, breakpoints, buttons (primary, secondary, ghost, deactivate, disabled, saving), form fields (required marker, inline error "AHM-01 is already used by Ahmedabad HQ. Choose another code.", optional field with helper), status badges (Active, Present, Pending, Late, Rejected, Missing punch, Invited, Inactive), tabs + breadcrumb, KPI card with "View list →", loading skeleton, empty state ("No employees match these filters" + Clear filters), error/retry.

### S02 · Components — pickers, multi-select, skeletons — `Components2.dc.html` · 1440 · Static
- **Date-range picker:** trigger shows range + day count; presets (Today, Tomorrow, Next week, This month, Last month, Custom); month grid Mon-first; today ringed; holidays dotted and noted "(not counted)"; Cancel / Apply; keyboard arrows + Enter.
- **Multi-select with chips:** typeahead combobox; inactive options disabled with "Inactive"; count "2 of 3 active branches selected"; chips collapse to "+N more" after 3; Backspace removes last chip.
- **Loading skeleton:** mirrors final layout; appears after 300 ms; `aria-busy`, screen-reader label "Loading employees"; shimmer off for reduced motion.
- **Side drawer:** 440 px desktop, full width < 600 px; modal, focus trapped, Esc closes; example = leave request quick view with Reject… / Approve.

---

## Stage 1 — Get in · Phase 2

### S03 · Welcome & employee sign-in — `Welcome.dc.html` · Fluid (drawn 1440) · Static
- **Who:** everyone. **Entry:** app root, "Sign in" links, "Back to sign in", sign-out, "Sign in again".
- **Layout:** two panes that wrap on narrow screens — dark brand pane (logo, headline "Attendance, leave and people records for every branch — in one place.", three ticked benefits, © · Privacy · Terms) and form pane (max 440 px).
- **Choice cards:** "Set up an organization — For owners creating a new workspace" (→ S04) and "Employee sign in — For staff, managers and admins" (selected).
- **Fields:** Work email or employee ID (`username`); Password with Show/Hide toggle; "Keep me signed in on this device" checkbox.
- **Actions:** Sign in (→ S06), Forgot password? (→ S07), Accept invitation (→ S09).
- **States:** failed sign-in banner (generic, does not reveal whether the account exists): "That email or employee ID and password don't match. Check both and try again."
- **Rule:** the card choice is navigation only; it grants nothing.

### S04 · Owner registration — `Register.dc.html` · Fluid (720) · Static
- **Who:** new owner. **Entry:** S03 card. **Next:** S05.
- **Header:** logo (→ S03), "Have an account? Sign in" (→ S03).
- **Fields:** Full name*; Work email*; Mobile number (optional) with country-code select (+91); Password* with show toggle, 4-segment strength meter and live rules — at least 10 characters · contains a number · upper and lower case letters · not your name or email (each ✓/· with screen-reader "met / not met"); Terms of Service and Privacy Policy checkbox*.
- **Errors shown:** "Accept the terms to continue."
- **Action:** Create account. Footnote "We'll email a 6-digit code to verify your address."

### S05 · Email verification — `Verify.dc.html` · Fluid (720) · **Live**
- **Who:** new owner. **Entry:** S04. **Next:** "Set up organization" → onboarding (S11/S12).
- **Content:** masked address ("an•••@meridiantex.in"), expires in 10 min.
- **Field:** 6-digit numeric code (non-digits stripped, max 6, one-time-code autofill).
- **Behaviour (confirmed):** Verify disabled until 6 digits; busy "Verifying…"; wrong code → red field + "That code isn't right. Check the latest email and try again."; editing clears the error; resend countdown "Resend in 0:45" then "Resend code" → "New code sent. Earlier codes no longer work."; success state "Email verified — Next, tell us about your organization." Prototype code `482913`.
- **Other:** "Use a different email" → S04.

### S06 · Sign-in — two-step verification — `SignInTwoStep.dc.html` · Fluid (720) · **Live**
- **Who:** returning user (required for admin roles). **Entry:** S03. **Next:** dashboard ("Continue to overview"); see D8 for org selection.
- **Modes:** authenticator 6-digit code ↔ backup code (`XXXX-XXXX`, uppercase, 9 chars max; "Each of your 10 backup codes works once. You have 8 left.").
- **Field help:** "Codes change every 30 seconds." / "Letters and numbers, like 7KQ2-M9XD."
- **Option:** "Don't ask again on this device for 30 days — Only on a computer you alone use."
- **Behaviour:** Verify disabled until valid format; "Checking…"; wrong → "That code didn't work. N tries left before a 15-minute pause."; after 3 wrong → locked: "Too many wrong codes. Sign-in is paused for 15 minutes. If this wasn't you, tell your owner — the attempts are in the audit log."; success "You're signed in" + note about backup codes left / trusted device.
- **Links:** Use a backup code instead / Use authenticator app instead; "Lost your phone and backup codes? Ask your organization owner…"; Sign in as someone else (→ S03). Prototype codes `482913`, `7KQ2-M9XD`.

### S07 · Forgot password (sent state) — `ForgotPassword.dc.html` · Fluid (720) · Static
- **Field:** Work email or employee ID. **Confirmation (always shown, never reveals existence):** "If an account matches, we've sent a reset link to its email. The link works once and expires in 30 minutes."
- **Actions:** Send again; Back to sign in. Note: "No work email on file? Ask your HR admin to send a reset link from your profile."
- ⚠ The initial "request" state (before sending) is not drawn; assume same form with a primary "Send reset link".

### S08 · Reset password — `ResetPassword.dc.html` · Fluid (720) · Static
- **Fields:** New password ("✓ Meets all requirements"), Confirm new password (error "Passwords don't match. Re-type the new password.").
- **Note:** "For is•••@meridiantex.in. You'll be signed out on other devices."
- **Action:** Update password → S03.
- **State:** link expired/used card — "This reset link has expired. Links work once and expire after 30 minutes. Your password hasn't changed." + Request a new link (→ S07).

### S09 · Invitation acceptance — `AcceptInvite.dc.html` · Fluid (720) · Static
- **Header:** "Hetal Shah invited you to join Meridian Textiles as Employee · Surat branch".
- **Read-only details (from HR):** Name, Employee ID, Email, Starts. "Tell them if anything is wrong."
- **Fields:** Create a password* (placeholder "At least 10 characters"), Confirm password*, agree to Terms + privacy notice*.
- **Action:** Accept and join → org selection or role home. Footer: "Invitation expires 21 Oct, 23:59", "Not you?" (→ S03).

### S10 · Organization selection — `OrgSelect.dc.html` · Fluid (720) · Static
- **List cards:** org initials, name, "Last used" chip, role · scope, branches · employees; a deactivated membership shows "Membership deactivated · history kept" (warning colour).
- **Actions:** pick → that org's home (Dashboard); "+ Set up another organization" → onboarding; Sign out.

---

## Stage 2 — Onboarding v2 · Phase 3

All 15 boards are one component (`OrgOnboarding.dc.html`). S11 is the live version; S12–S25 open it at a fixed scenario. Full state machine, validation text and progress formula: `navigation_flows.md` §3.

### S11 · Onboarding v2 — live prototype — `OrgOnboarding.dc.html` · 1440 (responsive) · **Live**
- Persists to browser storage (`staffline.onboarding.v2`) and offers "Continue where you left off" after reload; "Prototype data" reset. Sidebar links out to Employees, Attendance, Leave, Settings; org menu has "Switch organisation…" (→ S10), "Roles & Permissions"; notifications bell.

### S12 · 1 · First-time user, no organisation — scenario `noOrg`
- Top bar "Signed in as …  Sign out". Centre: icon, "Welcome to Staffline, Ankit", "Create your organisation workspace and get everything ready for your team.", primary **Set Up Your Organisation**, "Takes about a minute…", 4-step journey chips (Create organisation · Owner profile · First branch · Configure at your pace), "Joining an existing team instead? Use your invitation" (→ S09).

### S13 · 2 · Create organisation (3 fields) — scenario `createOrg`
- **Fields:** Organisation logo (optional; drag-and-drop or "Upload an image"; PNG/JPG/SVG ≤ 2 MB; preview with Replace / Remove); Organisation name; "How many people work here?" chip group: 1–10, 11–50, 51–200, 201–500, 501–1,000, 1,000+ ("Helps us suggest sensible defaults. You can change it later.").
- **Actions:** Cancel (→ S12), **Create Organisation** (busy "Creating…") → dashboard with loading skeleton then toast "<Org> is created. Next: your owner profile."; footnote "You can change any of this later in Settings."

### S14 · 2b · Create organisation — validation — scenario `createOrgError`
- Summary "Please fix 2 things before creating your organisation." + inline: "Enter your organisation name." / "Use at least 2 characters." / "Choose how many people work here."; logo errors "That file isn't an image. Use PNG, JPG or SVG." / "That image is over 2 MB. Choose a smaller one." / "We couldn't read that file. Try another." Typed values kept.

### S15 · 3 · New org, owner profile incomplete — scenario `ownerPending`
- App shell. "Welcome to Meridian Textiles". Card "Get Meridian Textiles ready — 1 of 3" with steps: Organisation created (Done) · Set up owner profile (**Set Up Owner Profile**, primary) · Set up your first branch (secondary). Branches empty state "No branches yet — A branch is one location — its address, working hours and its own rules." + Set Up Your First Branch. Header "✓ All changes saved".

### S16 · 3b · Owner profile form — scenario `ownerForm`
- Kicker "setup step 2 of 3". Fields: Profile photo (optional; Upload/Replace/Remove; same image rules); Full name (prefilled; "Enter your full name."); Email (read-only "From your sign-in", "Change it in your account settings."); Mobile number (prefilled, "From your registration. Used only for account recovery."; error "Enter a 10-digit mobile number, with or without +91."); Designation (optional, free text + chips Founder · Managing Director · Proprietor · HR Head).
- Actions: Back to dashboard, **Save Owner Profile** ("Saving…") → dashboard, toast "Owner profile saved. Next: your first branch." Header button "Save & go to dashboard".

### S17 · 4 · Owner done, no branch yet — scenario `ownerDone`
- "Welcome, Ankit — Owner profile saved. Set up your first branch so your team can start." Checklist 2 of 3; primary **Set Up Your First Branch**.

### S18 · 4b · First branch + weekly hours — scenario `branchForm` · 1440×1648
- Kicker "setup step 3 of 3" (or "· new branch" for later branches). **Branch details:** Branch name, Address, City, State (select: Gujarat, Maharashtra, Rajasthan, Madhya Pradesh, Karnataka, Delhi, Tamil Nadu, Other), PIN code (digits only, 6); "+ Add contact details (optional)" reveals Phone, Email.
- **Working hours:** summary "6 days · 54 h a week"; quick fill Mon–Sat · 9:30–18:30 / Mon–Fri · 9:00–18:00 / Every day · 10:00–20:00; per day: switch ("Open on Monday"), opening and closing time, hours, **Copy to…** (pick target days, "Select Mon–Sat", Cancel, "Apply to N days" → toast "Monday's hours copied to N days"); closed days shown "— Closed".
- Footnote: "Attendance rules, holidays, leave and permissions aren't needed now — they come next, one at a time, on the branch's setup checklist."
- Actions: Back to dashboard, **Create Branch** ("Creating…") → S20.

### S19 · 4c · Branch form — validation — scenario `branchFormError`
- Summary "Please fix 3 things below. Nothing you entered was lost." Inline: "Enter a branch name." / "You already have a branch with this name." / "Enter the branch address." / "Enter the city." / "PIN codes have 6 digits." / "Check the email address." / per day "Closing time must be after opening time." / "Open the branch on at least one day."

### S20 · 5 · Branch at 25 % — scenario `branchNew`
- Breadcrumb "Branches / Surat", status chip "Basics done". Hero: progress ring 25 %, "Basics are done — 5 short steps left", "Configure at your own pace — you can leave any time and pick up from here. Employees can already be added to this branch.", "How is progress calculated?" (weights popover), primary **Continue: attendance rules**.
- **Setup checklist** ("Required steps add to progress · optional ones don't"): Branch details & working hours +25 % (Edit) · Attendance rules +20 % · Holiday calendar +15 % · Leave policies +20 % · Roles & permissions +15 % · Reminders & notifications (optional) · Final review +5 % (Review; unlocks when the others are done). Row states: Done / Up next / To do / Needs attention / Optional / Set. Toast "Surat created · 25% set up".

### S21 · 6 · Branch partly configured — scenario `branchPartial`
- Ring 65 %, "3 of 6 required steps done". **Step side panel** (shown: Holiday calendar, "worth 15% of setup"): copy from another branch ("Copy from Ahmedabad HQ", "Copy from Vadodara" — only branches whose step is complete), sources (Gujarat public holidays · National holidays only · Start empty), list of holidays with observe toggle and remove for custom ones, add custom holiday (name, date, "every year"), "Close · keep draft" when dirty, **Save**. Other panels: see `navigation_flows.md` §3.4.

### S22 · 7 · Branch Setup Completed — scenario `branchDone` · 1440×1089
- Green banner "Branch Setup Completed — Ahmedabad HQ is ready. Employees added here can punch in, request leave and see holidays." Summary tiles: Working hours, Attendance, Holidays, Leave, Management. Actions **View Branch** (→ S38), Manage Branch, Add Another Branch. List "Manage branch configuration — Changes save immediately and keep the branch ready while valid." with Edit per step. Toast "Ahmedabad HQ is ready · 100% set up".

### S23 · 8 · Multi-branch, independent progress — scenario `multi`
- "Welcome, Ankit — 1 of 3 branches ready. Finish the rest whenever it suits you." Summary bar "Organisation set up · owner profile saved · 3 branches created" + Edit owner profile. Branch cards: ring %, name, address, status (Setup complete / In progress / Basics done / Needs attention), next step ("Next: holiday calendar" or "Fix: …"), primary **Continue Setup** (or "Complete Setup" ≥ 75 %, "View setup" at 100 %), Manage Branch. **Quick actions:** Add branch · Configure policies · Manage employees · View attendance · Open full dashboard (some appear only when relevant).

### S24 · 9 · Returning to unfinished setup — scenario `returning`
- Dark banner "Welcome back — pick up where you left off. You were setting up Surat (65%). Next: holiday calendar." Later / **Continue setup** (opens that branch's step).

### S25 · 10 · Loading skeleton — scenario `loading`
- Shell stays; content blocks become skeleton shapes matching the final layout; nothing clickable.

---

## Stage 3 — Onboarding v2 on small screens · Phase 3

| ID | Board | Width | What differs from desktop (confirmed) |
|---|---|---|---|
| S26 | `ObMobileBranchForm.dc.html` | 390 | Single column; each day stacked (switch, times, hours, Copy to…); sticky bottom bar Back to dashboard / Create Branch |
| S27 | `ObMobileBranchNew.dc.html` | 390 | Ring on top, stacked checklist rows each with its button underneath; hamburger + org switcher in header |
| S28 | `ObMobileMulti.dc.html` | 390 | Sidebar collapsed to hamburger; branch cards and quick actions stacked |
| S29 | `ObTabletMulti.dc.html` | 768 | Branch cards 2-up, quick actions 3-up |

---

## Stage 4 — Owner home · Phase 4 (shell parts in Phase 2)

### S30 · Owner overview dashboard — `Dashboard.dc.html` · 1440×1711 · Static
- **Who:** owner, HR admin. **Entry:** sign-in, "Open full dashboard", sidebar Overview.
- **Header:** "Good afternoon, Ankit", date · scope · counts. Filters: Branch (All, each branch), Period (Last 14 days, This month, Last 30 days), "Updated 2 min ago" refresh, **+ Add employee**.
- **Branch setup strip** (until all branches 100 %): per branch bar + %, "Setup complete / Next: …", View setup / Continue setup (→ onboarding).
- **KPI cards:** Total employees (+6 this month) · Active (7 inactive or invited) · Present today (79 % of scheduled) · Absent · late (3 more late than avg) · Working now (punched in, no punch-out) · Pending leave (2 waiting over 48h) · Upcoming holidays (next).
- **Charts:** Attendance trend (stacked on-time/late/absent per day, weekly offs & holidays hatched/excluded); Today, so far (donut: on time, late, on leave, absent, not punched yet); Headcount by branch (bars → branch); Leave taken by type (Casual, Sick, Earned, Unpaid); Scheduled vs worked hours (with note "excludes 41 days with missing punches until corrected").
- **Panels:** Pending leave approvals (rows → S57, "Open inbox"); Needs attention (Missing punch / Incomplete / Import / Change items → Attendance); Setup checklist (Organization profile, First branch, Work & leave policies, Add employees, Invite an HR admin [Start], Set up 2027 holidays [Start]) + upcoming holidays.

### S31 · Tablet dashboard — `TabletDashboard.dc.html` · 768 · Static
- Icon rail (expand button); filters stacked; KPIs 3-up (6 cards); trend chart; headcount + Needs attention (7 missing punches → S54, 1 import row failed → S51, 9 leave requests pending → S57); Pending approvals list.

### S32 · Mobile navigation drawer (admin) — `MobileNav.dc.html` · 390 · **Live** (open/close)
- Drawer over dimmed page: org + role header, close; **Branch** scope select (All branches / each); nav with count badges (Attendance 7, Leave Management 9, Notifications 3); user card + Sign out. Behind it: phone dashboard with KPI tiles.

### S33 · Branch Manager dashboard — `BranchDashboard.dc.html` · 1440 · Static
- **Who:** branch manager (Surat). Sidebar: Branch dashboard, Employees, Attendance exceptions (5), Leave approvals (3), Holidays, Branch reports.
- Branch lock chip "Branch: Surat" + period (Today / This week / This month). KPIs: Present 61 of 74 · Late 5 (avg 21 min) · Absent 4 (2 without leave) · On leave 3 · Working now 56 · Missing punches 5.
- Table "Today by department": Scheduled, Present, Late, On leave, Coverage bar (low coverage in warning colour).
- "Waiting for you" (leave requests, missing punch-out, coverage alert; All approvals → S57); "Off this week". Footnote "You see Surat only. Organization-wide numbers are available to the owner and HR."

### S34 · Leave Approver experience — `ApproverHome.dc.html` · 1440 · Static
- **Who:** leave approver (non-admin). Sidebar groups: ME (Home, My attendance, My leave, Holidays) and MY TEAM · 24 (Approvals 2, Team calendar ⚠ not designed).
- "2 requests need your decision — You approve leave for the 24 people who report to you. You see their leave and balances only." Cards: employee, type, dates, sent age, Balance after (or "Not enough · ask HR or switch to unpaid"), Team off those days, Reason; Reject… / Approve. "Recently decided by you" with Approved / Rejected / Withdrawn by employee. Footnote "Your own leave requests go to Jignesh Parmar — you can't approve them yourself."

---

## Stage 5 — Organisation and branches · Phase 3

### S35 · Organization profile — `OrgProfile.dc.html` · 1440 · **Live**
- **View mode:** header card (logo, name, legal name, counts, Active), sections General (Display name, Organization ID — read-only "Used in sign-in links. Can't be changed.", Industry, Default language), Legal & contact (Legal name *sensitive*, Registration number masked, Contact email, Contact phone), Address & time zone (Address, City · state · PIN, Country, Default time zone *sensitive*; "Branches inherit the time zone unless they set their own."), Branding (Logo, Brand color); footer "Created … last updated … View history" (→ S77).
- **Edit mode:** "Editing · not saved"; Cancel / Save changes. Sensitive fields flagged "· needs confirmation".
- **Confirm dialog** "Confirm sensitive changes" + "Notify HR admins about this change"; Go back / confirm (busy) → "Organization profile saved. The change is recorded in the audit log."

### S36 · Branch directory — `Branches.dc.html` · 1440 · Static
- "3 active · 1 inactive · 248 employees"; **+ Create branch** (→ S18 short form). Search "Name, code or city"; Any status; Sort (Employees high–low).
- Table: Branch (name + code) → S38, Address, Time zone ("Inherited · Asia/Kolkata"), Manager ("No manager"), Employees, Setup bar + % (→ onboarding), Status (Active/Inactive), Edit (→ S37). Footer "inactive branches keep all history and stay in reports".

### S37 · Create / edit branch — `BranchForm.dc.html` · 1440 · Static
- Full-page form with close (→ S38), Cancel, **Save branch**. Sections: Basic information (Branch name*, Branch code* — "Changing the code doesn't change existing employee IDs."); Address & contact (Address*, City*, PIN code*, Phone, Email); Time zone & calendar (Time zone*, Holiday calendar "Organization 2026 + Surat additions" — "2 branch-only holidays this year", Weekly off); Work schedule (working-day toggles Mon–Sun, Shift start, Shift end, Extra shift "Night 21:00–06:00 (overnight)", Effective from; "Changes apply from the effective date; past attendance is unchanged."); Managers & approvers (chips with role, remove, + Add person); Status (Active / Inactive — "78 employees must be moved to another branch first. History and reports are kept.").

### S38 · Branch details — `BranchDetail.dc.html` · 1440 · **Live** (tabs)
- Header: name, code, Active, address · time zone · manager; Deactivate… / **Edit branch** (→ S37). Setup banner "65% set up · attendance and roles done · next: holiday calendar · Continue setup".
- Tabs: Overview (KPIs Employees 78, Present today 61, Pending leave 3, Missing punches 5; Details), Employees · 78, Schedule & policies, Holidays · 2026, Managers & approvers, Activity.

---

## Stage 6 — People · Phase 4

### S39 · Employee directory — `Employees.dc.html` · 1440 · Static
- "248 people across 3 branches"; Template, Import (→ S46/S48), Export, **+ Add employee** (→ S43).
- Search "Search name, ID or email"; filters Branch, Department, Status, Type; Clear; Columns chooser.
- Bulk bar when rows selected: "2 selected · Resend invite · Change branch · Deactivate".
- Table (sortable Employee ↑): checkbox, avatar + name + ID · title (→ S42), Department, Branch, Manager, Employment (Active / Probation / Notice period / Inactive), Account (Signed in / Invited / Invite expired / No account), Joined, row actions menu. Pagination with Rows 10/25/50.

### S40 · Tablet employee directory — `TabletDirectory.dc.html` · 768 · **Live**
- 3 columns (Employee, Department, Today status) + ⋯; Filters button with count opens a **filter drawer** (Reset, "Show 78 people", Close); removable filter chips + Clear all; Choose columns. Note: "At 768 px the table keeps 3 columns. Branch, manager, schedule and joining date move into the row's profile."

### S41 · Directory as cards (mobile) — `MobileDirectory.dc.html` · 390 · Static
- Header with menu + round **+** add; search "Name or ID"; filter button with count; chip "Surat ×" + count; cards (avatar, name, title, ID chip, department, status) → S42; "Load 25 more".

### S42 · Employee details — `EmployeeProfile.dc.html` · 1440 · **Live** (tabs)
- Header: name, Active, "Signed in · 2h ago", ID · designation · department, branch · reports to (link) · joined · type; Reset password link, Deactivate…, **Edit** (→ S44).
- Tabs: Overview (At a glance, Work, Contact — masked mobile/emergency), Personal & employment, Attendance (month grid with legend P/L/A/H/W/missing), Leave & balances (Type, Granted, Used, Pending, Adjusted, Available; Adjust balance…), Schedule ("Inherited from Surat branch"), Account & access (status, last sign-in, method, two-step; role, scope, invitation, "Password — Never displayed"), Custom fields, Activity.

### S43 · Add / edit employee — `AddEmployee.dc.html` · 1440×2146 · Static
- Left section index with error dots: 1 Identity, 2 Contact information, 3 Employment details, 4 Organization & branch, 5 Reporting manager, 6 Work schedule & shift, 7 Attendance policy, 8 Custom fields, 9 Account & invitation.
- Fields: First name*, Last name*, Employee ID* ("Suggested next ID for Surat. You can change it."), Display name (opt); Work email* (dup error "This email belongs to Deepa Nair (EMP-0198). Use a different address."), Mobile (opt), Personal email (opt, "Only HR admins can see this."); Designation*, Department*, Employment type*, Joining date*, Probation ("From the Surat attendance policy."); Branch*, Work location (opt); Reports to* ("Leave requests route here first."); Shift* (error "Choose a shift. Surat has General (09:30–18:30) and Night (21:00–06:00)."), Weekly off (branch default); Policy (branch default); custom fields by department (e.g. Safety certification expiry*, Uniform size, Locker number); account & invitation toggles.
- Error summary at top ("2 fields need attention before saving" with jump links). Actions: **Save & send invite**, Save without inviting; close (→ S39).

### S44 · Edit employee — `EditEmployee.dc.html` · 1440 · Static
- Changed fields highlighted with "Changed" + "Was: …"; read-only fields (Employee ID "IDs never change once attendance exists.", Joining date "Ask the owner to correct this.", Mobile "Only the employee can change this.").
- Branch move with effective date shows consequences box ("Moving branches changes these too": schedule, reporting manager must be at new branch — required error, pending leave moves, holiday calendar switches).
- Side panel "Your changes" (old → new, audit note, employee notified). "3 changes" chip; Cancel; **Review & save**. Danger zone "Deactivate employee — Removes sign-in access. Attendance, leave and audit history are kept."

### S45 · Custom employee field builder — `FieldBuilder.dc.html` · 1440 · Static
- Left: draggable list (Reorder) with Required/Optional/Archived chips; **+ New field**.
- Editor: Label*, Field key (read-only "Used in imports and exports. Can't be changed."), Field type (locked "because values exist. Can switch to Multi-select only."), Description; Options list with per-option usage counts, remove disabled when in use ("Options in use can be renamed but not removed. Archive the field to stop collecting it."), + Add option; Required toggle with impact warning ("12 employees in Production have no value. They won't be blocked — HR will see them flagged as incomplete until filled.").
- "Who can see and edit" matrix (HR Admin, Branch Manager, Attendance Manager, Employee (self) × View/Edit); "Sensitive — hide from exports unless permitted"; Applies to (departments/branches); live preview. Archive / **Save field**.

---

## Stage 7 — Employee import · Phase 4

Six-step stepper on every screen: Upload · Map columns · Validate · Duplicates · Confirm · Results; close → S39. "Nothing is saved until you confirm on the last step."

| ID | Board | State | Content (confirmed) |
|---|---|---|---|
| S46 | `ImportUpload.dc.html` | **Live** | Drop zone ".xlsx or .csv · up to 5 MB · up to 2,000 rows · first row must be headers"; Choose file → upload progress → ready ("Continue to mapping"); rejected-file preview ("We can't read 'staff list.pdf'"); Download template; Recent imports table (File, By, Result, Report → S51) |
| S47 | `ImportMapping.dc.html` | Static | "We matched 12 of 14 columns by name." Table: Your column, Sample values, Import into (select incl. custom fields and "Don't import"), Check (Matched / Chosen by you / ! Check format / Custom field / Won't import). Right: Required fields checklist; **Date format** ambiguity choice DD/MM/YYYY vs MM/DD/YYYY with examples. Back / Validate 142 rows |
| S48 | `Import.dc.html` | Static | Counters Total 142 · Ready 131 · Warnings 6 · Duplicates 3 · Invalid 2 (filter toggles). "Rows with problems": Row, Employee ID, Name, Email, Branch, Joining date, Result (Invalid / Duplicate / Warning), What to fix. Download error report, Re-upload file. Back to mapping / Resolve 3 duplicates |
| S49 | `ImportDuplicates.dc.html` | **Live** | Policy cards: Reject duplicates (Default) · Update existing employees ("Needs 'Edit employees' permission") · Skip only identical rows. Table: Row · ID, Field, In system now, In your file, Will happen (Skipped / No change / Will update). Update requires acknowledgement checkbox ("I understand 1 existing employee record will be overwritten…") before continuing |
| S50 | `ImportConfirm.dc.html` | **Live** | Summary lines (Total, Valid, Warnings, Invalid skipped, Duplicates rejected, Employees to create / will be updated, Duplicate policy). "Send sign-in invitations" toggle (137 emails, expire in 7 days / accounts without access). Import → progress "Importing… keep this tab open" → "Server confirmed the import." → See results |
| S51 | `ImportResults.dc.html` | Static | "136 employees added to Surat — 1 row failed when saving and 5 were skipped. 136 invitations are being sent." Counters Created / Updated / Skipped / Failed. "Not imported · 6 rows" (Row, Employee, Outcome Failed/Skipped, Reason). Download error report (.xlsx), Import fixed rows (→ S46), View new employees (→ S39) |

---

## Stage 8 — Attendance · Phase 5

Attendance-manager sidebar (confirmed): Attendance overview, Records, Missing punches (7), Corrections (2), Monthly summary, Attendance exports; footnote "Your role can view and correct attendance. Employee profiles and roles are managed by HR."

### S52 · Attendance overview — `AttOverview.dc.html` · 1440 · **Live** (view toggle)
- Daily / Weekly / Monthly; branch and department filters. KPIs Present (of scheduled) · Late (avg min late) · Absent (+ on leave) · Incomplete (from yesterday) · Working now.
- "Arrivals today" histogram per 15 min (on time / late); branch table (Scheduled, Present, Late, Absent, Rate) → S53; Missing punches list (age chips) → S55, Open queue → S54; "Working right now" per-branch bars with "updated 14:10".

### S53 · Attendance records — `Attendance.dc.html` · 1440 · Static
- Daily/Weekly/Monthly, date picker, Export; KPIs; search Employee, department, chips "✓ Exceptions only", Late arrivals, Missing punch.
- Table: Employee, In, Out, Worked, Break, vs 8h (±), Status (Missing punch, Late, Left early, Absent, Half day, Short shift). "9 exceptions of 78 records · Show all records".
- **Detail panel** (selected row): alert "Session 2 has no punch-out. Worked time excludes it until corrected.", punch timeline with sources, Worked (confirmed) vs Expected, **Correct attendance…** (→ S55), "Corrections need a reason and are kept alongside the original punches in the audit log."

### S54 · Missing-punch queue — `MissingPunch.dc.html` · 1440 · Static
- "7 open sessions · worked time for these days is excluded until corrected"; filters branch, punch-in/punch-out; Remind all employees.
- Group "Overdue · older than 3 days — Blocks payroll export for these days" and "Recent — Employees can still request a correction". Rows: employee (→ S42), date, recorded events, state chip (No response / Reminded 13 Oct / Correction requested), actions Remind / Remind again / Reject request / Review request / Correct (→ S55). Empty branch: "Vadodara is all clear — No open sessions in the last 30 days."

### S55 · Attendance correction — `Correction.dc.html` · 1440 · **Live**
- Punches table (Event, Original, Corrected, Source); missing punch-out editable time; Worked (old struck through → new), Expected, Status after correction.
- Reason for correction* ("Saved in the audit log and shown to the employee."), min 5 chars; time must be after the last punch-in ("Punch-out must be after the 14:02 punch-in.").
- Policy note: correction needs second approver because corrector is the employee's manager → routed to HR admin; record stays "Missing punch" until approved.
- Right: employee card, Employee's request (proposed time + quote), Correction history. **Send for approval** ("Sending…") → "Sent for approval. Original punches are kept. Back to queue".

### S56 · Monthly attendance summary — `MonthlySummary.dc.html` · 1440 · **Live**
- Month select, Team grid / Day list toggle, Export. Legend P · L · ½ · A · LV · H · W · ! Grid employees × days with totals (Present, Late, Absent, Leave). "Late counts as present; half day counts 0.5." Selecting a name shows that person's day list with Correct actions.

---

## Stage 9 — Leave administration · Phase 6

HR-admin Leave Management sub-tabs: Approvals · Requests · Balances · Leave types · Policy.

### S57 · Leave approval inbox + detail — `LeaveApprovals.dc.html` · 1440 · **Live**
- Pending / Decided / All; search; sort Oldest first / Start date. List rows (age warns when old; status chips Pending / Routed to HR).
- Detail: type, dates, duration, submitted, reason, Balance impact (available now → after approval), Team on these dates ("2 of 24 in Production already off", excludes holiday and weekly offs), history.
- Actions: **Approve**, Request changes, Reject… → inline "Reason for rejection*" (shared with employee; min 3 chars) → Reject request. Busy "Saving decision — waiting for the server…"; decided text "✓ Approved — X has been notified. N days deducted." / "× Rejected — … notified with your reason." Own/manager request auto-"Routed to HR — approver cannot approve own request".
- ⚠ "Request changes" behaviour not drawn.

### S58 · Leave type management — `LeaveTypes.dc.html` · 1440 · Static
- Type list (colour dot, Paid · allowance, Active/Inactive), **+ New type**. Editor (Unsaved changes, Discard, Save): Basics (Name, Pay, Track a balance), Allowance & accrual (Method, Per month, Starts after — "Changed from 6 months · applies to new joiners only"), Carry forward & expiry (up to, expire, Encashment), Rules (min/max per request, Attachment, Allow half days, Weekends/Holidays inside a request), Eligibility (employment types, branches, departments); worked example.

### S59 · Leave policy configuration — `LeavePolicy.dc.html` · 1440 · Static
- Approval routes table (Applies to, Step 1, Step 2, If approver is away; Edit; + Add route) — "Nobody approves their own request — it skips to the next step."
- Request rules: Notice for planned leave (days ahead), Backdated sick leave (error "Must be 30 days or less, so attendance for a closed month isn't changed."), Longest single request; Blackout periods (+ Add period).
- Balance treatment: Reserve balance for pending requests (always on), Allow negative balance, Cancel approved leave that hasn't started, Require approval again when dates change (always on); Leave year; Round balances to.
- "Unsaved changes · last saved 14:40"; View change history; save disabled "Fix 1 error to save".

### S60 · Balances & adjustments — `LeaveBalances.dc.html` · 1440 · **Live**
- Table per employee: Casual, Sick, Earned, Pending (negatives in red with minus); Adjust → side form: Leave type, Change (days, ±, non-zero, |x| ≤ 30), Effective date, preview "2.5 → 3.5", Reason* (≥ 5 chars, shown to employee + audit). Save → "Adjustment saved … Logged as evt_…" / Make another. Export balances.

### S61 · Leave request history — `LeaveRequests.dc.html` · 1440 · **Live** (status chips)
- Search; type, branch, period filters; status chips All · Pending · Approved · Rejected · Amended · Withdrawn · Cancelled; Export. Table: Request ID (→ S57), Employee, Type · dates (amended shows old → new), Days, Status, Decision ("decisions are permanent; changes show as amendments").

---

## Stage 10 — Holidays and schedules · Phase 6

| ID | Board | State | Content (confirmed) |
|---|---|---|---|
| S62 | `Holidays.dc.html` | **Live** | "Holiday calendar 2026 — 14 holidays · 11 organization-wide · 3 branch-specific"; month nav, branch filter, Month / Year / List views; legend Organization-wide · Branch-specific · Optional/floating · Weekly off; holiday chips → edit (S64); Import / export, **+ Add holiday** |
| S63 | `HolidayDirectory.dc.html` | Static | Tabs Calendar · Holiday list · Import/export · Schedules. Search, year, scope, Export. Table Date ↑, Holiday, Category, Applies to (scope chips), Status (Past / In 6 days / Upcoming · on a weekly off), View (past) / Edit (future) — "past holidays can't be edited because attendance already used them" |
| S64 | `HolidayForm.dc.html` | Static | Holiday name*; Length single day / date range; Date* (warning "Tue 10 Nov is already 'Diwali break' for all branches. Save anyway only if this replaces it."); Category (Festival, National, Regional, Company); Description; Who gets it: Whole organization (incl. future branches) / Selected branches (checkboxes); Optional holiday. "What this changes" impact panel (employees affected, approved leave returned, scheduled shifts, notifications). Cancel / **Save holiday** |
| S65 | `HolidayImport.dc.html` | Static | Import preview of a file: Row, Date, Holiday, Scope, Result (Ready / Duplicate / Invalid "September has 30 days"); "Duplicates and invalid rows will be skipped." Choose another file / Add 13 holidays. Export: Year, Scope, XLSX/CSV, Download; blank template link |
| S66 | `ScheduleAssign.dc.html` | Static | Precedence "1 Employee override › 2 Shift group › 3 Branch › 4 Organization" (most specific wins). Assignments table (Applies to, Schedule, Weekly off, Effective, People; scheduled future rows highlighted). New assignment: Apply to, Schedule, Weekly off, Effective from; impact note + "Attendance before 1 Nov stays calculated against the old schedule."; **Schedule change** |

---

## Stage 11 — Access · Phase 7

Sub-tabs: Roles · People & access · Invitations.

| ID | Board | State | Content (confirmed) |
|---|---|---|---|
| S67 | `RoleDirectory.dc.html` | Static | **+ Create role**. Table Role (+ description), Type (System 🔒 / Custom), Scope (Organization-wide / Assigned branches / Own team / Own records), People (→ S70), Status, Actions (View or Edit, Duplicate). "System roles can be viewed and duplicated but not edited. The last owner can't be removed or downgraded." |
| S68 | `Roles.dc.html` | Static | Data scope radio (Organization-wide / Assigned branches / Own records only). Permission matrix modules × actions (View, Create, Edit, Deactivate, Approve, Correct, Export); cells granted / owner-only 🔒 / not applicable; changed cells highlighted. Pending changes list + warning "Applies immediately to … They'll be signed out of open sessions." Assigned people (Manage → S70). "3 unsaved changes", Discard, **Review & save** |
| S69 | `MobileRoles.dc.html` | 390 | Same role as collapsible module sections with toggles and "n of m allowed", "Edited" chips, owner-only notes; sticky "3 unsaved changes · Discard · Review" |
| S70 | `UserRoles.dc.html` | **Live** | Search, filter "Roles above Employee". Table Person, Role, Branch scope, Membership (Active/Invited), Change role → dialog (New role select). Last owner blocked: "X is the only owner. Make someone else an owner first…". High-impact (to/from Owner or HR Admin) shows impact text and "Confirm high-impact change". Toast "X is now Y. They'll see the change at next page load." |
| S71 | `Invitations.dc.html` | Static | KPIs Waiting · Expired · Not delivered · Accepted (30 days). Filter "Not yet accepted", Resend all expired (3). Table Person, Role · branch, Invited (by/when or Import), Expires, Status (Waiting / Expired / Not delivered "Mail server rejected the address"), Resend or Edit email, Revoke. "People set their own password from the invitation link. Passwords are never shown or emailed." |
| S72 | `AccessDenied.dc.html` | Static | Inside the user's own shell: "You don't have access to this page — Roles & Permissions is managed by the organization owner. Your role, Branch Manager, covers the Surat branch." **Go to your dashboard** / Ask the owner for access ⚠ (flow not drawn). "If you followed a link someone shared, they may have more access than you. Reference 403 · req_…" |

---

## Stage 12 — Reports, notifications and audit · Phase 7

| ID | Board | State | Content (confirmed) |
|---|---|---|---|
| S73 | `Reports.dc.html` | Static | "Reports only include branches and fields your role can access." Catalogue grouped People (Employee roster, Employee changes), Attendance (Daily attendance, Monthly attendance summary, Missing-punch report), Leave (Leave balance, Leave requests & decisions), Calendar & compliance (Holiday calendar, Audit log — owner and HR admin only). Configure panel: From/To, Branch, Department, Columns (some always included, some "not permitted for your role"), Preview row count, XLSX/CSV, View results (→ S74), **Export**. Recent exports (Ready → Download, Generating, Failed → Retry); "Download links expire after 7 days" |
| S74 | `ReportResults.dc.html` | Static | Filter chips + Change filters; generated-at note incl. data caveat ("figures exclude 7 days still marked missing punch"); totals; table (sortable) with pagination; Export CSV / **Export XLSX** |
| S75 | `ExportHistory.dc.html` | Static | Filters (Anyone you can see / Only me; report; period). Table Report, Requested by, Created, Status (Ready / Generating "About 1 min" / Failed + Retry / Expired "Run again to download" / "Owner only"). "Downloads use the same permissions as the data. Links expire after 7 days and every download is logged." |
| S76 | `AdminNotifications.dc.html` | **Live** | Category chips All · Approvals · Attendance · People · System; list (icon, title, time, unread dot); detail panel with body, key facts and action button (e.g. Review request → S57); Mark all read; Notification settings (→ S82). "Notifications never include passwords, attachments or restricted fields." |
| S77 | `AuditLog.dc.html` | Static | "Append-only. Entries can't be edited or deleted by anyone." Filters period, actor, action, entity, branch, Clear; Export. Table Time, Actor (+ role), Action code (e.g. `attendance.correct`, `employee.update`, `leave.approve`, `role.update`, `leave.reject`, `import.commit`, `policy.update`, `auth.signin_failed`), Entity, Summary (→ S78). Side detail: event id, actor, scope, record link, source + masked IP, reason, Before/After table; "Sensitive values … are masked". Newer / Older paging |
| S78 | `AuditEvent.dc.html` | Static | Event header (action, time); What changed (Before/After); People affected (sessions signed out); Related events (re-authentication, sessions ended, previous edit); Context (actor, entity, scope, reason, source, masked IP, event ID); "Entry is sealed — linked to the previous entry by checksum…" |

---

## Stage 13 — Settings · Phase 7 (attendance/leave/schedule parts reused from Phases 5–6)

Settings left index (confirmed): Organization · Branches · Work schedules · Attendance policy · Leave policy · Employee fields · Notifications · Security · Data & export · Branding & localization. Search settings. Every page shows "Unsaved changes" / Discard / Save, or "✓ All changes saved · time".

| ID | Board | State | Content (confirmed) |
|---|---|---|---|
| S79 | `Settings.dc.html` | Static | Attendance policy (policy selector "Factory floor v2 — used by Surat and Vadodara · 122 employees"): Late arrival & early departure (Grace period — "Changed from 10 min", Mark half day if late by, Early departure threshold, Repeated lateness); Missing punches & corrections (Open session at end of day: Flag for correction / Close at shift end / Count as half day; Employees can request corrections within N days; Corrections approved by; reason always required); Display & overtime (Round worked time, Flag overtime after, Changes take effect date — "Past attendance keeps the policy it was recorded under."); Change history (→ S77) |
| S80 | `SettingsOverview.dc.html` | **Live** | Cards per area with summary meta and warnings; warning banner "2 things need attention: two-step sign-in is off for 3 admins, and 2027 holidays aren't set up yet."; search filters cards; no-match "No settings match 'q'. Try a broader word…" |
| S81 | `SettingsSchedules.dc.html` | Static | Schedule cards (General, Office, Night +1, Half-day) with usage; editor: Name, Starts, Ends ("Next day (overnight)"), Expected hours (computed minus unpaid breaks); Breaks (window, duration, paid/unpaid; + Add break); overnight attribution (shift start day vs split at midnight); Changes take effect; + New schedule; Save schedule |
| S82 | `SettingsNotifications.dc.html` | Static | Matrix events × recipient (Employee / Manager / HR Admin) × channel (In-app / Email) grouped Leave, Attendance, People & account, Calendar; locked items (invitation always sent); "Security emails … are always sent and can't be turned off." Daily digest for managers (toggle, send at, branch local time); email preview; Edit email templates ⚠ |
| S83 | `SettingsSecurity.dc.html` | **Live** | Two-step sign-in: Optional / Required for admin access (Recommended) / Required for everyone; "Not set up yet: …" list. Passwords & sessions: Minimum length, Lock after failed attempts, Sign out inactive users after, Invitation links expire after, Password reset links expire after, Account recovery. Save requires **"Confirm it's you"** password dialog → "✓ Saved · logged in the audit trail" |
| S84 | `SettingsData.dc.html` | Static | Who can export (roles × People/Attendance/Leave/Restricted fields; Owner always); Export format (date format, durations, CSV separator, download link expiry); Retention (attendance punches, deactivated employees then anonymized, export files, Audit log 7 years 🔒 min); Audit log access (Owner always, HR Admin, Branch Managers — their branches) "Nobody can edit or delete audit entries, including the owner." |
| S85 | `SettingsBranding.dc.html` | Static | Logo (SVG/PNG square ≥ 256×256; Replace/Remove); Brand color swatches Indigo (default), Navy, Teal, Rust + Custom hex with contrast warning ("White text on this color is hard to read (1.9:1). We'll use dark text…"); Language & formats (Default language English (India) / ગુજરાતી / हिन्दी — "Employees can pick their own in My profile."; Date format; Time format 24h/12h; Numbers Indian/International; Week starts on); live preview |

---

## Stage 14 — Employee self-service (phone, 390 px) · Phases 5–6

Bottom tab bar on every screen: Home · Attendance · Leave · Holidays · Profile.

| ID | Board | State | Content (confirmed) | Phase |
|---|---|---|---|---|
| S86 | `EmpHome.dc.html` | **Live** | "Good morning, Isha — Wed 14 Oct · Surat · Shift 09:30–18:30"; status chip (Punched in since / Punched out / Sending…); Current session live timer hh:mm:ss; Today total; progress vs 8 h; **Punch in / Punch out** (busy "Punching out…"; never changes state until server confirms; failure "Punch not recorded. We couldn't reach the server. Your status hasn't changed — try again."); "Expected 8h 00m · 60m break", Today's punches (→ S88); correction notice "Your 13 Oct punch-out was corrected to 18:34 by Mitesh Rana. View"; Leave balance tiles + pending request (→ S91), Apply (→ S89); Recent attendance (→ S88), History (→ S87); Upcoming holidays; bell with unread | 5 |
| S87 | `MyAttendance.dc.html` | Static | Month select (incl. Custom range…); KPIs Present (of working days), Late (avg), Worked (vs expected), Leave (pending); day rows (date, in → out, "Session in progress", "Corrected by …", "28 min late", worked, status chip) → S88; "Something wrong? Open the day and tap 'Request correction' within 3 days." | 5 |
| S88 | `DayDetail.dc.html` | Static | Worked / Expected / Break (of allowed) / Shift; Timeline (punch in with source and lateness, break start/end, punch out "Added by correction · original: none"); Exceptions (LATE …, FIXED …); **Request correction** ("Available until Fri 16 Oct · goes to Aarav Bhatt") ⚠ request form not drawn | 5 |
| S89 | `ApplyLeave.dc.html` | Static | Leave type* (shows days available); From*, To*; Duration Full days / First half / Second half; "You'll use N days" breakdown per day (counted, holiday not counted, overlaps pending); balance after; overlap warning "This overlaps your pending request for Mon 19 Oct. Withdraw it first, or change the start date to Wed 21 Oct."; Reason (optional, "Visible to your approver"); "Goes to Aarav Bhatt. You'll get a notification when it's decided."; **Submit request** disabled "Resolve the overlap to submit." | 6 |
| S90 | `MyLeave.dc.html` | Static | **+ Apply for leave**; Balances · 2026 (stacked bar used / pending / available, granted & lapse notes); Next approved leave; Recent requests with status chips (Pending, Approved, Rejected + reason, Cancelled) → S91; History (→ S92) | 6 |
| S91 | `LeaveDetail.dc.html` | **Live** | Type, dates, duration, status; Submitted, Request ID, Balance after, Approver, Your reason; Progress timeline (Submitted → Waiting for approver → Decision); Change dates ("Changes send the request for approval again." → S89); Withdraw request → confirm sheet "Withdraw this request?" Keep / Withdraw ("Withdrawing…") → "Request withdrawn. 1 day is back in your casual balance and Aarav has been told." | 6 |
| S92 | `LeaveHistory.dc.html` | Static | Filters type/year/status; "Casual · how 4 days is worked out" (Granted, Used, Held for pending, Adjustments by HR, Available); Transactions ledger newest first (Pending −1, Rejected ±0, Used −2, Granted +8, Lapsed −2.5) with running balance | 6 |
| S93 | `MyHolidays.dc.html` | **Live** | Month calendar (Holiday, Optional, Your approved leave, Today), month nav, list of the month's holidays with scope; "Shows organization holidays and those for Surat. Optional holidays need a leave-style request." | 6 |
| S94 | `MyProfile.dc.html` | Static | Contact ("You can edit these": Mobile, Emergency contact — Edit; Preferred language — Change; Work email); Employment ("Managed by HR", locked: Branch, Manager, Shift, Joined; "Something wrong? Ask HR to update"); Account & security (Password Change, Two-step verification Off — recommended → Turn on, Signed-in devices Manage) ⚠ sub-flows not drawn; Sign out | 2/4 |
| S95 | `EmpNotifications.dc.html` | **Live** | All / Unread (2); groups Today / Earlier; items (Attendance corrected, Holiday next week, Leave approved, Profile updated, Leave not approved, Announcement) → linked screen; Mark all read | 7 |

---

## Stage 15 — Platform admin and system states

| ID | Board | State | Content (confirmed) | Phase |
|---|---|---|---|---|
| S96 | `SystemStates.dc.html` | Static | Nine states in real screens: Empty first run (No employees yet → Import spreadsheet / Add employee); Empty all done (Nothing waiting for you → See decided requests); Empty expected (No attendance expected — Dussehra → View holiday); Filters return nothing (→ Change filters); Page didn't load (Try again + reference id); Record not found (404 → Go to directory); Offline punch ("You're offline — Saved on this phone · will sync. The time you tapped is kept…"); Session expired ("You were signed out … your unsaved holiday form is kept — sign in again to finish it."); Conflict while saving ("Neha Iyer changed this policy 2 minutes ago … Compare changes / Discard mine") | 1 (components) + each phase |
| S97 | `PlatformOrgs.dc.html` | Static | Platform-admin shell (dark sidebar: Organizations, Support access, Plans & billing, Platform audit, System status; "You see organization settings and usage — not employee records. Opening one needs the owner's approval."); "Signed in as platform admin · 2-step verified"; KPIs (Organizations, Employees on platform, In trial, Suspended, Open support sessions); search, status, plan filters; table Organization (id), Owner, Plan, Branches, Employees, Status (Active/Trial/Setup incomplete/Suspended), Last activity; Export list | 7 (optional) |
| S98 | `PlatformOrgDetail.dc.html` | **Live** | Usage tiles, Owner & plan; **Support access** — read-only timed session approved by owner (reason, scope, ends at) → Open workspace (read-only), End session now → ended note; Platform action log; Owner account help (Reset owner two-step…); Suspend organization → dialog with reason select and "Type the org ID to confirm" | 7 (optional) |

⚠ Platform nav items Support access, Plans & billing, Platform audit, System status have no boards.

---

## Not designed but referenced (⚠ summary)

Employee correction-request form · "Ask the owner for access" request · Two-step setup, change password, signed-in devices (My profile) · Edit own contact / emergency contact · Approver "Team calendar" · Attendance "Corrections" list and "Attendance exports" pages · Leave "Request changes" flow · Create/duplicate role (reuses S68?) · New leave type (reuses S58 editor) · Forgot-password request state · Email template editor · Employee terminate / transfer flow beyond Edit · Ownership transfer · Platform: Support access list, Plans & billing, Platform audit, System status · Kiosk punch mode (attendance method "Shared kiosk") · Employee screens at tablet/desktop widths · Admin screens (other than nav, directory, roles) at phone width. See `open_questions.md` Q-12.
