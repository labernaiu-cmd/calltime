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
3. **Deploy** (Vercel) — see below.

None of steps 2–3 are required to try live mode locally: open
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

**What actually sends mail today:**
- Rehearsal reminders (teacher → roster)
- Post-rehearsal notes (teacher → roster)
- Excuse approved/denied notices (fires automatically when a teacher
  decides an excuse)
- The "Absence notice" template, fired automatically the moment a teacher
  marks a student absent on the Today tab

**What doesn't**, because it needs something to run on a schedule
independent of any user click (a Vercel cron job or Supabase Edge
Function, neither of which this project has yet):
- The "Absence warning" / "Failing risk" rules (`after_absence` trigger —
  meant to fire when a student crosses the free-absence threshold)
- Pre-event reminders (`before_event` trigger)
- Auto-checkout at an event's end time (`attendance.auto_checkout`)

## 3. Deploy (Vercel)

```bash
npm install -g vercel
npm install          # installs resend + @supabase/supabase-js for api/send-email.js
vercel login
vercel --prod
```

In the Vercel dashboard, set these environment variables (Project →
Settings → Environment Variables) before your first deploy, or the
`/api/send-email` function will fail at runtime:

```
SUPABASE_URL=https://xxxxx.supabase.co
SUPABASE_ANON_KEY=eyJ...
RESEND_API_KEY=re_...
```

`vercel.json` rewrites `/` to `calltime.html` so you don't need to rename
the file to `index.html`. After deploying, add the deployed URL to
Supabase's **Authentication → URL Configuration → Redirect URLs** (magic
links only redirect to allow-listed URLs) — see `supabase/README.md` §4.

## Known gaps

Kept out of scope rather than half-built. In rough order of "you'd
probably notice this first":

- **File attachments on excuses** aren't uploaded to Supabase Storage —
  they're stored inline as base64 data URLs in the `excuses.attachment_url`
  column. Fine for a small photo, not for anything large or numerous.
- **Absence → grade recompute**: approving or denying an excuse updates
  the excuse's own status but never recalculates `ensemble_members.absences`
  or the student's grade. This was already true in the original prototype
  (`decideExc()` never touched absence counts even with mock data) and
  wiring it needs a decision about what "excused" should do to the count,
  not just a database call.
- **Recurring events** are decorative — picking "Every week" in the New
  Event modal appends a text label to the event name; it does not create
  multiple event rows.
- **QR check-in** generates a real, scannable QR code, but it encodes a
  fake URL (`calltime.app/checkin?event=tonight`) with no route behind it
  anywhere in this project.
- **Auto-checkout** and the **scheduled notification rules** — see above.
