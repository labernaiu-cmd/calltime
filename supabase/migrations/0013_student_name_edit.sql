-- Lets a student correct their own display name on the roster — e.g. when
-- it was auto-derived from their email at invite-link join time (see
-- handleJoinDeepLink()/nameFromEmail() in calltime.html) instead of their
-- actual name, since magic-link sign-in collects no name by default.
--
-- Constrained via WITH CHECK to require the row still be role='student' and
-- status='active' after the update, so this can't be used to self-promote
-- to teacher or reactivate a denied/removed membership — only `name` (and
-- incidentally `part`/`email`) are realistically editable through it.
create policy "Students can update their own member row"
  on ensemble_members for update
  using (user_id = auth.uid())
  with check (user_id = auth.uid() and role = 'student' and status = 'active');
