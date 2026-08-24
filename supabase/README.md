# Supabase setup

> This file covers the database only. For app email (Gmail SMTP) and
> Vercel (hosting) setup, see the root [`README.md`](../README.md).

## 1. Create the project

1. Go to [supabase.com](https://supabase.com) → New project.
2. Once it's provisioned, go to **Project Settings → API** and copy:
   - **Project URL** → `SUPABASE_URL`
   - **anon public** key → `SUPABASE_ANON_KEY`

## 2. Run the migrations

In the Supabase dashboard, open **SQL Editor** and run the files in this
folder in order (or use the Supabase CLI: `supabase db push`):

1. `migrations/0001_init_schema.sql` — tables from spec §1.2, plus
   `ensembles.created_by` (needed so a new ensemble's creator can add
   themselves as its first teacher — see below) and indexes on the
   foreign keys every query/policy filters on.
2. `migrations/0002_rls_policies.sql` — Row Level Security for every
   table, implementing spec §1.3 ("teachers can do everything in their
   ensembles; students can read events, read their own attendance/excuses,
   insert check-ins"):
   - `ensembles` — readable by any signed-in user (an invite link has to
     resolve for whoever opens it — see migration 0012), writable only by
     that ensemble's teacher.
   - `ensemble_members` — a user always sees their own row; teachers see
     every row in their ensemble. A user can insert an `active` `student`
     row for themselves (superseded by migration 0012 — originally
     `pending`, back when joining went through a teacher-approval queue) or,
     if they created the ensemble, a `teacher` row for themselves. Teachers
     can insert/update/delete any member row (add students, edit roles).
   - Everything else (`events`, `attendance`, `excuses`,
     `grading_policies`, `resources`, `rehearsal_notes`) — readable by any
     active member of the ensemble; writable by that ensemble's teacher.
     `attendance`/`excuses` additionally let a student insert/update their
     *own* row (check in/out, submit an excuse).
   - `email_templates` and `notification_rules` — teacher-only in both
     directions; the UI never shows these to students.

   Two helper functions, `is_ensemble_teacher(ensemble_id)` and
   `is_ensemble_member(ensemble_id)`, back most of these policies. They're
   `security definer` so they can read `ensemble_members` without
   triggering that table's own RLS recursively.
3. `migrations/0003_ensemble_members_invite.sql` — lets a teacher add a
   student to the roster (or import a CSV/pasted list) before that student
   has ever signed in. Adds `email`/`name` columns to `ensemble_members`
   for these not-yet-linked rows, a partial unique index so the same
   email can't be invited to an ensemble twice, and a trigger on
   `auth.users` that backfills `user_id` the moment someone signs up with
   a matching email.
4. `migrations/0004_attendance_realtime.sql` — adds `attendance` to the
   `supabase_realtime` publication so the teacher's Today view can
   subscribe to check-ins live (`supabase.channel(...).on('postgres_changes', ...)`)
   instead of polling or requiring a refresh.
5. `migrations/0005_rehearsal_notes_unique_event.sql` — adds a unique
   index on `rehearsal_notes.event_id` (missing from the original schema),
   needed for `savePreNotes()`/`savePostNotes()` to upsert one notes row
   per event instead of erroring or creating duplicates.
6. `migrations/0006_excuse_attachments_storage.sql` — creates a private
   `excuse-attachments` Storage bucket (photos/PDFs of doctor's notes etc.
   were previously embedded as base64 in `excuses.attachment_url`, which
   works but bloats the table) with policies so a student can upload/view
   their own files and a teacher can view any file under an ensemble they
   teach, keyed by the `<ensemble_id>/<user_id>/...` path.
7. `migrations/0007_notification_log.sql` — only needed if you're setting
   up the Vercel Cron job (root `README.md` §3). Dedupes the two
   timer-based notification rules so they don't re-email the same student
   on every cron tick.
8. `migrations/0008_exclude_excused_absences.sql` — adds
   `grading_policies.exclude_excused_absences` (default `true`), the
   setting behind the wizard's "Excused absences" step and Settings >
   Grading's matching toggle: whether an approved excuse removes that
   absence from the free-absence/failing-threshold and grade-deduction
   math, or counts the same as an unexcused one.
9. `migrations/0009_ensemble_timezone.sql` — adds `ensembles.tz` (IANA
   name, default `'America/Chicago'`), captured from the creating
   teacher's browser when they finish the setup wizard.
   `events.event_date`/`start_time`/`end_time` stay unqualified wall-clock
   strings, but `api/cron/tick.js` needs to know what timezone those
   strings are *in* to correctly compare them against its own (UTC, on
   Vercel) clock — see `zonedTimeToUtc()` there.
10. `migrations/0010_points_grading_model.sql` — adds
    `grading_policies.points_total`/`points_per_event`/`points_mode`, a
    third grading model (alongside `pct`/`letter`) selected in Settings >
    Grading: a points pool a student either has deducted from per absence
    or earns toward per rehearsal attended. See `pointsBalance()` in
    `calltime.html`.
11. `migrations/0011_ensemble_archive.sql` — adds `ensembles.archived_at`,
    behind Settings > General's "Archive ensemble" (a reversible way to get
    an old ensemble out of the landing list, as opposed to "Delete
    ensemble" there, which is permanent and cascades through every table).
12. `migrations/0012_invite_link_join.sql` — replaces the old
    "request to join, teacher approves" flow with invite links: a teacher
    copies a per-ensemble link (Roster tab or Settings > General) and
    shares it directly; a student who opens it while signed in is added as
    an *active* member immediately, no approval step. Swaps the RLS policy
    that let a student self-insert a `pending` row for one that allows
    `active` instead. See `copyInviteLink()`/`handleJoinDeepLink()` in
    `calltime.html`.
13. `migrations/0013_student_name_edit.sql` — lets a student update their
    own `ensemble_members` row (used for the pencil icon next to their name
    in the student topbar — see `saveEditName()`), constrained via
    `WITH CHECK` to keep `role='student'`/`status='active'` so it can't be
    used to self-promote to teacher or reactivate a removed membership.
    Needed because magic-link sign-in collects no name by default, so a
    student who joined via invite link before this migration (or before
    the login screen's name field existed) would otherwise be stuck with
    whatever `nameFromEmail()` guessed from their email address.
14. `migrations/0014_claim_preinvited_row.sql` — lets a student link their
    own account to a roster row a teacher pre-added by email
    (`addStudent()`/CSV import) before that account existed or ever signed
    in. Migration 0003's trigger only backfills `user_id` when signing in
    creates a *brand-new* `auth.users` row — an account that already
    existed at invite time (a returning student, or anyone re-testing with
    a previously-used email) never gets linked automatically, and RLS
    otherwise hides an unlinked row (`user_id is null`) from everyone but
    that ensemble's teacher. See `claimPreInvitedRows()` in
    `calltime.html`, called on every sign-in.

## 3. Enable email auth

**Authentication → Providers → Email** should already be on by default.
(For SMTP — routing sign-in emails through a real account instead of
Supabase's own rate-limited sender — see the root `README.md`'s Email
section; this build uses Gmail SMTP.)

**Authentication → Email Templates → Magic Link** needs one edit: replace
the default clickable-link template with one that shows `{{ .Token }}` (a
6-digit code) as plain text instead of `{{ .ConfirmationURL }}` as a link
— e.g.:

```
Your Call Time sign-in code is: {{ .Token }}

This code expires shortly. If you didn't request this, you can ignore this email.
```

This isn't cosmetic — it's required for sign-in to work reliably.
Institutional email (Office 365 Safe Links/ATP and similar corporate mail
security scanners) commonly auto-visits every link in an incoming message
to scan it, which silently consumes a one-time magic-link token before the
actual recipient ever clicks it — so anyone on a scanned inbox would see
"Email link is invalid or has expired" on *every* sign-in attempt, with no
way to fix it from the app side. `calltime.html`'s login flow (see
`sendMagicLink()`/`verifyOtpCode()`) accordingly never relies on the link
at all — it calls `signInWithOtp()` then `verifyOtp({ email, token, type:
'email' })` with the code the user types in. If the template still
contains `{{ .ConfirmationURL }}` *in addition to* `{{ .Token }}`, a
scanner visiting that link will still burn the shared one-time-password
record and invalidate the code too — the link needs to be gone from the
template entirely, not just de-emphasized.

## 4. Wire the frontend

In `calltime.html`, find:

```js
const SUPABASE_URL = 'YOUR_SUPABASE_URL';
const SUPABASE_ANON_KEY = 'YOUR_SUPABASE_ANON_KEY';
```

and replace both placeholders with the values from step 1. The anon key
is safe to ship in client-side code — it has no privileges beyond what
the RLS policies above grant it.

There's no Redirect URLs allow-list entry to add for sign-in itself —
since it's code-based (§3), the user never leaves the page, so nothing
ever redirects back. The QR check-in link (`?checkin=<eventId>&ensemble=
<ensembleId>`, see `handleCheckinDeepLink()`) and ensemble invite link
(`?join=<ensembleId>`, see `handleJoinDeepLink()`) aren't Supabase
redirects either — they're plain URLs a teacher shares directly, opened
like any other link.
