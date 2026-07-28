-- Call Time — Phase 1: Row Level Security
-- Implements calltime-spec.md §1.3: "Teachers can do everything in their
-- ensembles; students can read events, read their own attendance/excuses,
-- insert check-ins" — extended to every table in the schema.
--
-- ensemble_members is read from within its own RLS policies (a member row
-- decides who may see other member rows), which would normally recurse.
-- The two helper functions below are SECURITY DEFINER so they read
-- ensemble_members directly, bypassing RLS, and only ever return a
-- boolean — safe to call from any policy.

create or replace function is_ensemble_teacher(p_ensemble_id uuid)
returns boolean
language sql
security definer
set search_path = public
stable
as $$
  select exists (
    select 1 from ensemble_members
    where ensemble_id = p_ensemble_id
      and user_id = auth.uid()
      and role = 'teacher'
      and status = 'active'
  );
$$;

create or replace function is_ensemble_member(p_ensemble_id uuid)
returns boolean
language sql
security definer
set search_path = public
stable
as $$
  select exists (
    select 1 from ensemble_members
    where ensemble_id = p_ensemble_id
      and user_id = auth.uid()
      and status = 'active'
  );
$$;

alter table ensembles enable row level security;
alter table ensemble_members enable row level security;
alter table events enable row level security;
alter table attendance enable row level security;
alter table excuses enable row level security;
alter table grading_policies enable row level security;
alter table resources enable row level security;
alter table email_templates enable row level security;
alter table rehearsal_notes enable row level security;
alter table notification_rules enable row level security;

-- ENSEMBLES
-- Selectable by any signed-in user (students need to browse/join ensembles
-- they aren't members of yet — see the "join request" flow in the UI).
create policy "Any signed-in user can view ensembles"
  on ensembles for select
  to authenticated
  using (true);

create policy "Any signed-in user can create an ensemble"
  on ensembles for insert
  to authenticated
  with check (created_by = auth.uid());

create policy "Teachers can update their ensembles"
  on ensembles for update
  using (is_ensemble_teacher(id));

create policy "Teachers can delete their ensembles"
  on ensembles for delete
  using (is_ensemble_teacher(id));

-- ENSEMBLE_MEMBERS
create policy "Members can view their own row or their teachers can view all"
  on ensemble_members for select
  using (user_id = auth.uid() or is_ensemble_teacher(ensemble_id));

create policy "Users can request to join as a student"
  on ensemble_members for insert
  with check (user_id = auth.uid() and role = 'student' and status = 'pending');

create policy "Ensemble creator can bootstrap themself as teacher"
  on ensemble_members for insert
  with check (
    role = 'teacher' and user_id = auth.uid()
    and exists (select 1 from ensembles where id = ensemble_id and created_by = auth.uid())
  );

create policy "Teachers can add or approve members"
  on ensemble_members for insert
  with check (is_ensemble_teacher(ensemble_id));

create policy "Teachers can update members"
  on ensemble_members for update
  using (is_ensemble_teacher(ensemble_id));

create policy "Teachers can remove members"
  on ensemble_members for delete
  using (is_ensemble_teacher(ensemble_id));

-- EVENTS
create policy "Members can view events"
  on events for select
  using (is_ensemble_member(ensemble_id));

create policy "Teachers can insert events"
  on events for insert
  with check (is_ensemble_teacher(ensemble_id));

create policy "Teachers can update events"
  on events for update
  using (is_ensemble_teacher(ensemble_id));

create policy "Teachers can delete events"
  on events for delete
  using (is_ensemble_teacher(ensemble_id));

-- ATTENDANCE
create policy "Students can view their own attendance, teachers view all"
  on attendance for select
  using (user_id = auth.uid() or is_ensemble_teacher(ensemble_id));

create policy "Students can insert own check-ins"
  on attendance for insert
  with check (
    (user_id = auth.uid() and is_ensemble_member(ensemble_id))
    or is_ensemble_teacher(ensemble_id)
  );

create policy "Students can update own attendance, teachers update all"
  on attendance for update
  using (user_id = auth.uid() or is_ensemble_teacher(ensemble_id));

create policy "Teachers can delete attendance"
  on attendance for delete
  using (is_ensemble_teacher(ensemble_id));

-- EXCUSES
create policy "Students can view their own excuses, teachers view all"
  on excuses for select
  using (user_id = auth.uid() or is_ensemble_teacher(ensemble_id));

create policy "Students can submit their own excuses"
  on excuses for insert
  with check (user_id = auth.uid() and is_ensemble_member(ensemble_id));

create policy "Teachers can decide on excuses"
  on excuses for update
  using (is_ensemble_teacher(ensemble_id));

create policy "Teachers can delete excuses"
  on excuses for delete
  using (is_ensemble_teacher(ensemble_id));

-- GRADING_POLICIES
create policy "Members can view grading policy"
  on grading_policies for select
  using (is_ensemble_member(ensemble_id));

create policy "Teachers can insert grading policy"
  on grading_policies for insert
  with check (is_ensemble_teacher(ensemble_id));

create policy "Teachers can update grading policy"
  on grading_policies for update
  using (is_ensemble_teacher(ensemble_id));

create policy "Teachers can delete grading policy"
  on grading_policies for delete
  using (is_ensemble_teacher(ensemble_id));

-- RESOURCES
create policy "Members can view resources"
  on resources for select
  using (is_ensemble_member(ensemble_id));

create policy "Teachers can insert resources"
  on resources for insert
  with check (is_ensemble_teacher(ensemble_id));

create policy "Teachers can update resources"
  on resources for update
  using (is_ensemble_teacher(ensemble_id));

create policy "Teachers can delete resources"
  on resources for delete
  using (is_ensemble_teacher(ensemble_id));

-- EMAIL_TEMPLATES (teacher-only; students never see these in the UI)
create policy "Teachers can view email templates"
  on email_templates for select
  using (is_ensemble_teacher(ensemble_id));

create policy "Teachers can insert email templates"
  on email_templates for insert
  with check (is_ensemble_teacher(ensemble_id));

create policy "Teachers can update email templates"
  on email_templates for update
  using (is_ensemble_teacher(ensemble_id));

create policy "Teachers can delete email templates"
  on email_templates for delete
  using (is_ensemble_teacher(ensemble_id));

-- REHEARSAL_NOTES
create policy "Members can view rehearsal notes"
  on rehearsal_notes for select
  using (is_ensemble_member(ensemble_id));

create policy "Teachers can insert rehearsal notes"
  on rehearsal_notes for insert
  with check (is_ensemble_teacher(ensemble_id));

create policy "Teachers can update rehearsal notes"
  on rehearsal_notes for update
  using (is_ensemble_teacher(ensemble_id));

create policy "Teachers can delete rehearsal notes"
  on rehearsal_notes for delete
  using (is_ensemble_teacher(ensemble_id));

-- NOTIFICATION_RULES (teacher-only)
create policy "Teachers can view notification rules"
  on notification_rules for select
  using (is_ensemble_teacher(ensemble_id));

create policy "Teachers can insert notification rules"
  on notification_rules for insert
  with check (is_ensemble_teacher(ensemble_id));

create policy "Teachers can update notification rules"
  on notification_rules for update
  using (is_ensemble_teacher(ensemble_id));

create policy "Teachers can delete notification rules"
  on notification_rules for delete
  using (is_ensemble_teacher(ensemble_id));
