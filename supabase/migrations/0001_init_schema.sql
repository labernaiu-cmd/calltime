-- Call Time — Phase 1: initial schema
-- Mirrors calltime-spec.md §1.2, with two additions needed to make
-- §1.3 (RLS) actually enforceable:
--   1. ensembles.created_by — lets a newly-created ensemble's creator
--      bootstrap themselves as its first 'teacher' member (see 0002).
--   2. updated_at on a few tables that the UI edits in place.

create extension if not exists pgcrypto;

-- ENSEMBLES
create table ensembles (
  id uuid primary key default gen_random_uuid(),
  name text not null,
  sub text,
  term text,
  teacher_name text,
  teacher_email text,
  color text default '#534AB7',
  description text,
  schedule text,
  drive_url text,
  created_by uuid references auth.users(id),
  created_at timestamptz default now()
);

-- ENSEMBLE MEMBERS (links users to ensembles with a role)
create table ensemble_members (
  id uuid primary key default gen_random_uuid(),
  ensemble_id uuid references ensembles(id) on delete cascade,
  user_id uuid references auth.users(id) on delete cascade,
  role text default 'student', -- 'teacher' | 'student'
  part text, -- e.g. 'Lead', 'Ensemble', 'Stage crew'
  status text default 'active', -- 'active' | 'pending' | 'denied'
  absences int default 0,
  created_at timestamptz default now(),
  unique(ensemble_id, user_id)
);

-- EVENTS (calendar)
create table events (
  id uuid primary key default gen_random_uuid(),
  ensemble_id uuid references ensembles(id) on delete cascade,
  name text not null,
  type text default 'Rehearsal',
  event_date date not null,
  call_time text,
  start_time text,
  end_time text,
  venue text,
  dress text,
  program jsonb, -- array of strings
  notes text,
  geo_lat float,
  geo_lng float,
  geo_radius int default 50,
  created_at timestamptz default now()
);

-- ATTENDANCE
create table attendance (
  id uuid primary key default gen_random_uuid(),
  event_id uuid references events(id) on delete cascade,
  user_id uuid references auth.users(id) on delete cascade,
  ensemble_id uuid references ensembles(id) on delete cascade,
  status text default 'absent', -- 'present' | 'late' | 'absent'
  checkin_at timestamptz,
  checkout_at timestamptz,
  auto_checkout boolean default false,
  unique(event_id, user_id)
);

-- EXCUSES
create table excuses (
  id uuid primary key default gen_random_uuid(),
  attendance_id uuid references attendance(id) on delete cascade,
  user_id uuid references auth.users(id) on delete cascade,
  ensemble_id uuid references ensembles(id) on delete cascade,
  type text,
  text text,
  attachment_url text,
  status text default 'pending', -- 'pending' | 'approved' | 'denied'
  teacher_note text,
  submitted_at timestamptz default now(),
  reviewed_at timestamptz
);

-- GRADING POLICIES (one per ensemble)
create table grading_policies (
  id uuid primary key default gen_random_uuid(),
  ensemble_id uuid references ensembles(id) on delete cascade unique,
  model text default 'pct', -- 'pct' | 'letter'
  free_absences int default 2,
  fail_threshold int default 4,
  deduction_pct int default 5,
  tardies_per_absence int default 3,
  late_window_min int default 10,
  letter_style text default 'half', -- 'half' | 'full'
  letter_rules jsonb, -- [{absences: 3, drop: 1}, ...]
  excuse_window_hours int default 48
);

-- RESOURCES
create table resources (
  id uuid primary key default gen_random_uuid(),
  ensemble_id uuid references ensembles(id) on delete cascade,
  title text not null,
  type text default 'document',
  url text,
  description text,
  created_at timestamptz default now()
);

-- EMAIL TEMPLATES
create table email_templates (
  id uuid primary key default gen_random_uuid(),
  ensemble_id uuid references ensembles(id) on delete cascade,
  key text not null, -- 'absence' | 'warning' | 'failing' | 'exc_app' | 'exc_den' | 'custom_*'
  label text,
  subject text,
  body text,
  unique(ensemble_id, key)
);

-- REHEARSAL NOTES
create table rehearsal_notes (
  id uuid primary key default gen_random_uuid(),
  event_id uuid references events(id) on delete cascade,
  ensemble_id uuid references ensembles(id) on delete cascade,
  pre_notes text,
  post_notes text,
  post_sent_at timestamptz,
  updated_at timestamptz default now()
);

-- NOTIFICATION RULES
create table notification_rules (
  id uuid primary key default gen_random_uuid(),
  ensemble_id uuid references ensembles(id) on delete cascade,
  label text,
  enabled boolean default true,
  trigger text, -- 'end_of_event' | '30_after_start' | etc.
  offset_value int default 0,
  offset_unit text default 'min',
  template_key text
);

-- Indexes on the foreign keys every RLS policy and list-view query filters on.
create index on ensemble_members (ensemble_id);
create index on ensemble_members (user_id);
create index on events (ensemble_id);
create index on attendance (event_id);
create index on attendance (user_id);
create index on attendance (ensemble_id);
create index on excuses (attendance_id);
create index on excuses (user_id);
create index on excuses (ensemble_id);
create index on resources (ensemble_id);
create index on email_templates (ensemble_id);
create index on rehearsal_notes (event_id);
create index on rehearsal_notes (ensemble_id);
create index on notification_rules (ensemble_id);
