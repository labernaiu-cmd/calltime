-- Replaces the browse-all-ensembles "request to join" flow with invite
-- links: a teacher shares a per-ensemble link (?join=<ensembleId>, see
-- copyInviteLink() in calltime.html), and a student who opens it while
-- signed in is added as an active member immediately — clicking the link
-- *is* the approval, so there's no more pending/approve/deny step.
--
-- The old policy only let a student self-insert with status='pending'
-- (a request awaiting a teacher's decision); this replaces it with one
-- that allows status='active' instead, matching the new flow.
drop policy if exists "Users can request to join as a student" on ensemble_members;

create policy "Users can join as an active student via invite link"
  on ensemble_members for insert
  with check (user_id = auth.uid() and role = 'student' and status = 'active');
