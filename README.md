# Call Time

Rehearsal attendance management for performing ensembles — magic-link auth,
real-time check-in/out, geofencing, and email notifications, all on
Supabase + Vercel + Resend. See `calltime-spec.md` for the original
technical handoff this was built from.

The whole frontend is one file, `calltime.html` — no build step. It runs in
two modes:
- **Demo mode** ("Skip for now" on the login screen) — the original
  hardcoded mock data, no network calls, works with zero setup.
- **Live mode** (a real magic-link sign-in) — backed by Supabase for
  everything below.

## Setup, in order

1. **Database** — see [`supabase/README.md`](supabase/README.md): create
   the Supabase project, run the migrations, enable email auth, and drop
   your project URL/anon key into `calltime.html`.
2. **Email** (Resend) — see below.
3. **Scheduled jobs** — see below. Optional; only auto-checkout and two of
   the notification rules depend on it.
4. **Deploy** (Vercel) — see below.

None of steps 2–4 are required to try live mode locally: open
`calltime.html` (e.g. `python3 -m http.server` and visit it) once step 1 is
done, and everything except outbound email will work.

## 2. Email (Resend)

1. Create an account at [resend.com](https://resend.com).
2. Either verify your own sending domain, or use `onboarding@resend.dev`
   for testing (Resend restricts that address to sending to your own
   verified account email — fine for trying things out, not for real
   students).
3. Copy your API key.

The actual sending happens server-side in `api/send-email.js` — the
browser never talks to Resend directly. That function requires a valid
Supabase session token on every request (see the comment at the top of the
file) so it can't be used as an open relay once deployed; it does *not*
check that the caller is actually allowed to email the given recipient
(e.g. a teacher of that student's ensemble) — worth adding via a
service-role Supabase client before this handles real student data at
scale.

**What sends mail, and how:**
- Rehearsal reminders, post-rehearsal notes, and excuse approved/denied
  notices — user-triggered, via `api/send-email.js` (needs Resend only).
- The "Absence notice" template — fires automatically the moment a teacher
  marks a student absent, same path as above.
- "Absence warning" / "Failing risk" (`after_absence`) and pre-event
  reminders (`before_event`) — these depend on a schedule, not a user
  action, so they run separately in `api/cron/tick.js`. See step 3.
- **Auto-checkout** (`attendance.auto_checkout`) also lives in
  `api/cron/tick.js`, even though it doesn't send mail — same reason: it
  needs to run when an event's end time passes, not when someone clicks
  something.

## 3. Scheduled jobs (Vercel Cron)

`api/cron/tick.js` runs auto-checkout and the two timer-based notification
rules described above. It needs its own Supabase client with the
**service role** key (not the anon key) since it acts across every
ensemble on a timer, not on behalf of one signed-in user — grab it from
**Project Settings → API → service_role** (keep this one server-side only;
it bypasses every RLS policy in `supabase/migrations/`).

1. Run `supabase/migrations/0007_notification_log.sql` (dedupes sends so
   these rules don't re-fire on every cron tick — see its comments).
2. Set a `CRON_SECRET` env var to any random string; Vercel automatically
   sends it as `Authorization: Bearer $CRON_SECRET` when it invokes a
   scheduled function, and `tick.js` checks for exactly that.
3. `vercel.json` declares the schedule as `0 6 * * *` — once a day. Vercel's
   **Hobby plan only allows daily cron jobs**, not shorter intervals, so
   this is the fastest schedule that deploys without a paid plan. That
   means auto-checkout and the absence-warning/pre-event-reminder emails
   only run once a day rather than near-real-time — acceptable for trying
   things out, but worth knowing about. If you're on (or upgrade to) a
   **Pro plan**, you can tighten this to something like `*/15 * * * *`
   (every 15 minutes) for much faster turnaround. Alternatively, skip
   Vercel Cron's limit entirely by pointing an external scheduler (a free
   uptime-monitor/cron-ping service works fine) at
   `https://yourapp.vercel.app/api/cron/tick` with the `CRON_SECRET`
   header, at whatever frequency you like.

Skipping this step entirely is fine — everything else in the app works
without it. You'll just have attendance rows that never auto-checkout, and
the "Absence warning"/"Failing risk"/pre-event-reminder rules will sit
enabled in Settings without ever firing.

## 4. Deploy (Vercel)

```bash
npm install -g vercel
npm install          # installs resend + @supabase/supabase-js for api/
vercel login
vercel --prod
```

In the Vercel dashboard, set these environment variables (Project →
Settings → Environment Variables) before your first deploy:

```
SUPABASE_URL=https://xxxxx.supabase.co
SUPABASE_ANON_KEY=eyJ...
SUPABASE_SERVICE_ROLE_KEY=eyJ...   # only needed for api/cron/tick.js — see step 3
RESEND_API_KEY=re_...
CRON_SECRET=any-random-string      # only needed for api/cron/tick.js — see step 3
```

`vercel.json` rewrites `/` to `calltime.html` so you don't need to rename
the file to `index.html`. After deploying, add the deployed URL to
Supabase's **Authentication → URL Configuration → Redirect URLs** (magic
links only redirect to allow-listed URLs) — see `supabase/README.md` §4.

## Known gaps

Kept out of scope rather than half-built:

- **Excuse decisions don't recompute a *letter* grade** — approving a
  student's excuse now correctly removes that absence from the `pct`
  model's free-absence/failing-threshold/deduction math (or not, per the
  wizard/Settings > Grading "Excused absences" toggle — see
  `gradedAbsences()`), and the roster's absence count is always a live
  count from real `attendance` rows so it's never stale. But selecting the
  `letter` grading model in Settings only changes what the settings tab
  itself shows (`letterRules`) — nothing in `renderRoster()`/
  `getReportData()` branches on `gradeModel` to actually apply
  letter-grade math to a real student, excused absences or otherwise.
- **Recurring events, weekly/Mon-Wed/Mon-Wed-Fri presets**, are capped at
  16 weeks (`SEMESTER_WEEKS` — a semester) and **custom recurrence with
  "never" as its end** is capped at 52 occurrences instead — both are
  guardrails against an unbounded insert, not a real "repeats forever"
  feature. See `computeRecurrenceDates()`.
