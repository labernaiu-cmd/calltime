-- Lets a student claim a pre-invited ensemble_members row — one a teacher
-- created via addStudent()/CSV import (email set, user_id null) before
-- this account ever existed or ever signed in. Migration 0003's trigger
-- only backfills user_id when a *new* row is inserted into auth.users, so
-- an account that already existed at invite time (a returning student, or
-- anyone re-testing with a previously-used email) never gets linked
-- automatically — and RLS otherwise hides an unlinked row (user_id is
-- null) from everyone but that ensemble's teacher, so there'd be no way
-- for the student to ever find or claim it themselves.
create policy "Students can claim their own pre-invited member row"
  on ensemble_members for update
  using (user_id is null and email is not null and lower(email) = lower((auth.jwt() ->> 'email')))
  with check (user_id = auth.uid() and role = 'student' and status = 'active');
