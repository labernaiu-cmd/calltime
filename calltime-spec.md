# Call Time — Backend Spec for Claude Code

## What this document is
A complete technical handoff for wiring the Call Time prototype (`calltime.html`) to a real backend. The UI is fully built. This spec covers everything needed to make it persistent, multi-user, and production-ready.

---

## Stack

| Layer | Technology | Why |
|---|---|---|
| Database + Auth | Supabase (free tier) | Postgres + magic link auth built in |
| Email sending | Resend (free tier, 3k/mo) | Simple API, great deliverability |
| Hosting | Vercel (free tier) | One-click deploy, serverless functions |
| Frontend | Vanilla HTML/JS (existing file) | No framework needed |

---

## Phase 1 — Supabase Setup

### 1.1 Create project
- Go to supabase.com → New project
- Note: `SUPABASE_URL` and `SUPABASE_ANON_KEY`

### 1.2 Database schema

```sql
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
```

### 1.3 Row Level Security (RLS)

Enable RLS on all tables. Key policies:

```sql
-- Teachers can do everything in their ensembles
-- Students can read events, read their own attendance/excuses, insert check-ins

-- Example for attendance:
create policy "Students can insert own check-ins"
  on attendance for insert
  with check (auth.uid() = user_id);

create policy "Teachers can read all attendance in their ensembles"
  on attendance for select
  using (
    exists (
      select 1 from ensemble_members
      where ensemble_id = attendance.ensemble_id
      and user_id = auth.uid()
      and role = 'teacher'
    )
  );
```

### 1.4 Auth — Magic Link

```javascript
// In the app, replace sendMagicLink() with:
const { error } = await supabase.auth.signInWithOtp({
  email: email,
  options: {
    emailRedirectTo: 'https://your-app.vercel.app/auth/callback'
  }
})
```

Enable "Email" provider in Supabase Auth settings. No SMTP config needed for magic links — Supabase handles it.

For teacher's Jewell email routing (future): configure custom SMTP in Supabase Auth settings using Office 365 SMTP credentials.

---

## Phase 2 — Frontend Integration

### 2.1 Add Supabase client

Replace the `<script>` tag in `calltime.html`:

```html
<script src="https://cdn.jsdelivr.net/npm/@supabase/supabase-js@2"></script>
<script>
  const supabase = window.supabase.createClient('YOUR_SUPABASE_URL', 'YOUR_ANON_KEY')
</script>
```

### 2.2 Data layer swaps

Every place the app reads/writes a JS array, swap for a Supabase call. Examples:

**Load ensembles on landing:**
```javascript
// OLD
renderLanding() // reads from ensembles[] array

// NEW
async function loadEnsembles() {
  const { data } = await supabase
    .from('ensembles')
    .select('*, ensemble_members!inner(role)')
    .eq('ensemble_members.user_id', supabase.auth.getUser().id)
  ensembles = data
  renderLanding()
}
```

**Check in:**
```javascript
// OLD
s.s = 'present'; s.t = fmt12(time); renderAll()

// NEW
async function checkIn(eventId) {
  const { data } = await supabase
    .from('attendance')
    .upsert({
      event_id: eventId,
      user_id: supabase.auth.getUser().id,
      ensemble_id: activeEns().id,
      status: 'present',
      checkin_at: new Date().toISOString()
    })
}
```

**Key functions to rewrite:**
- `renderAll()` → async, loads from Supabase
- `toggleCI()` → writes attendance record
- `saveEvent()` → inserts into events table
- `addStudent()` / `importPasted()` / `importCSV()` → inserts into ensemble_members
- `submitExc()` → inserts into excuses
- `decideExc()` → updates excuse status
- `saveResource()` / `deleteResource()` → insert/delete resources
- `saveTpl()` → upsert email_templates
- `saveAll()` (grading) → upsert grading_policies
- `savePreNotes()` / `savePostNotes()` → upsert rehearsal_notes

### 2.3 Real-time presence (optional but impressive)

```javascript
// Teacher sees check-ins appear live without refreshing
supabase
  .channel('attendance-changes')
  .on('postgres_changes', {
    event: 'INSERT',
    schema: 'public',
    table: 'attendance',
    filter: `ensemble_id=eq.${activeEns().id}`
  }, (payload) => {
    // Update the today-list in real time
    updateStudentStatus(payload.new)
  })
  .subscribe()
```

---

## Phase 3 — Email Sending (Resend)

### 3.1 Setup
- Create account at resend.com
- Add and verify your domain (or use onboarding@resend.dev for testing)
- Get API key

### 3.2 Vercel serverless function

Create `/api/send-email.js` in your project:

```javascript
import { Resend } from 'resend'
const resend = new Resend(process.env.RESEND_API_KEY)

export default async function handler(req, res) {
  const { to, subject, body, from } = req.body

  const { data, error } = await resend.emails.send({
    from: from || 'calltime@yourdomain.com',
    to,
    subject,
    text: body,
  })

  if (error) return res.status(400).json({ error })
  return res.status(200).json({ data })
}
```

### 3.3 Future: Route through Jewell account
When ready, configure Supabase Auth custom SMTP:
- Host: `smtp.office365.com`
- Port: `587`
- Username: `labernathy@william.jewell.edu`
- Password: App password generated from Microsoft account security settings

---

## Phase 4 — Geolocation

The UI already has all the geo-fence logic. Just uncomment/wire:

```javascript
// In toggleCI(), before marking present:
function checkGeoFence(eventLat, eventLng, radiusMeters, callback) {
  navigator.geolocation.getCurrentPosition(pos => {
    const dist = getDistanceMeters(
      pos.coords.latitude, pos.coords.longitude,
      eventLat, eventLng
    )
    callback(dist <= radiusMeters, dist)
  }, () => callback(true, 0)) // fail open if GPS unavailable
}

function getDistanceMeters(lat1, lon1, lat2, lon2) {
  const R = 6371e3
  const φ1 = lat1 * Math.PI/180
  const φ2 = lat2 * Math.PI/180
  const Δφ = (lat2-lat1) * Math.PI/180
  const Δλ = (lon2-lon1) * Math.PI/180
  const a = Math.sin(Δφ/2)**2 + Math.cos(φ1)*Math.cos(φ2)*Math.sin(Δλ/2)**2
  return R * 2 * Math.atan2(Math.sqrt(a), Math.sqrt(1-a))
}
```

---

## Phase 5 — Deploy to Vercel

```bash
npm install -g vercel
vercel login
vercel --prod
```

Set environment variables in Vercel dashboard:
```
SUPABASE_URL=https://xxxxx.supabase.co
SUPABASE_ANON_KEY=eyJ...
RESEND_API_KEY=re_...
```

---

## File structure after conversion

```
calltime/
├── index.html          (the existing calltime.html, renamed)
├── api/
│   ├── send-email.js   (Resend serverless function)
│   └── auth-callback.js (Magic link redirect handler)
├── package.json
└── vercel.json
```

---

## Priority order for Claude Code

1. **Supabase project + schema** — run the SQL above
2. **Auth** — swap `bypassLogin()` for real magic link
3. **Ensemble CRUD** — load/save ensembles from DB
4. **Attendance** — check-in/out writing to DB, real-time updates
5. **Email sending** — Resend integration for absence emails
6. **Everything else** — excuses, resources, templates, etc.

Steps 1–4 alone make the app genuinely usable for a real rehearsal.

---

## Key context for Claude Code

- The prototype is a **single HTML file** (~4,000 lines). All JS is in one `<script>` tag at the bottom.
- Global state lives in arrays: `ensembles[]`, `students[]`, `evList[]`, `excuses[]`, `resources[]`
- `activeEnsIdx` tracks which ensemble is loaded; `loadEnsembleContext()` / `saveEnsembleContext()` swap state in/out
- The app has **no build step** — plain HTML/CSS/JS, no React, no bundler
- When converting to async/await, wrap render functions and add loading states
- The teacher is **Dr. Lawrence Abernathy** at William Jewell College (`labernathy@william.jewell.edu`)
- Three ensembles: **Cardinal Voices**, **Concert Choir**, **Choral Scholars**
