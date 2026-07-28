-- Call Time — Phase 2.2: ensemble CRUD support
--
-- The roster UI lets a teacher add a student by name/email (addStudent,
-- importPasted, importCSV) before that student has ever signed in — there's
-- no auth.users row for them yet, so ensemble_members.user_id can't be set
-- at insert time. Store the invite's email/name directly on the row, and
-- backfill user_id automatically via trigger the moment that email signs up.

alter table ensemble_members
  add column email text,
  add column name text;

-- One invite per email per ensemble. Partial index because rows created
-- through the "student requests to join" flow always have a user_id and
-- may reasonably share a null/blank email otherwise.
create unique index ensemble_members_ensemble_email_key
  on ensemble_members (ensemble_id, lower(email))
  where email is not null;

create or replace function link_ensemble_member_on_signup()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  update ensemble_members
     set user_id = new.id
   where lower(email) = lower(new.email)
     and user_id is null;
  return new;
end;
$$;

create trigger on_auth_user_created_link_member
  after insert on auth.users
  for each row execute function link_ensemble_member_on_signup();
