# Supabase setup (Phase 1 + Phase 2)

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
   - `ensembles` — readable by any signed-in user (students need to browse
     ensembles to send join requests), writable only by that ensemble's
     teacher.
   - `ensemble_members` — a user always sees their own row; teachers see
     every row in their ensemble. A user can insert a `pending` `student`
     row for themselves (a join request) or, if they created the ensemble,
     a `teacher` row for themselves. Teachers can insert/update/delete any
     member row (approve/deny requests, add students, edit roles).
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

## 3. Enable email auth

**Authentication → Providers → Email** should already be on by default.
No SMTP configuration is needed for magic links — Supabase sends them.
(Routing outbound mail through the Jewell Office 365 account is a later,
optional step — see spec §3.3.)

## 4. Wire the frontend

In `calltime.html`, find:

```js
const SUPABASE_URL = 'YOUR_SUPABASE_URL';
const SUPABASE_ANON_KEY = 'YOUR_SUPABASE_ANON_KEY';
```

and replace both placeholders with the values from step 1. The anon key
is safe to ship in client-side code — it has no privileges beyond what
the RLS policies above grant it.

Also add your deployed URL (or `http://localhost:...` while developing)
to **Authentication → URL Configuration → Redirect URLs**, since magic
links only redirect back to allow-listed URLs.
