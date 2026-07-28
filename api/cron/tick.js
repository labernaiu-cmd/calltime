// Vercel Cron target (see vercel.json's "crons") — the only piece of Call
// Time that runs on a timer instead of in response to a user action:
//   1. Auto-checkout: close out attendance rows nobody manually checked
//      out of, once their event's end time has passed.
//   2. after_absence rules: "Absence warning" / "Failing risk" — fires
//      once a student's total absence count crosses free_absences+1 or
//      fail_threshold.
//   3. before_event rules: pre-event reminders, offset_value/offset_unit
//      before the event's start_time.
//
// Uses the service-role key (bypasses RLS — this runs for every ensemble,
// not on behalf of any one signed-in user) and is protected by CRON_SECRET,
// which Vercel sends automatically as `Authorization: Bearer $CRON_SECRET`
// for scheduled invocations once that env var is set.
import { createClient } from '@supabase/supabase-js';
import { Resend } from 'resend';

const supabase = createClient(process.env.SUPABASE_URL, process.env.SUPABASE_SERVICE_ROLE_KEY);
const resend = new Resend(process.env.RESEND_API_KEY);

function renderTokens(text, values) {
  let out = text || '';
  Object.entries(values).forEach(([k, v]) => { out = out.split(k).join(v ?? ''); });
  return out;
}

async function sendMail(to, subject, body) {
  try {
    await resend.emails.send({ from: 'Call Time <calltime@yourdomain.com>', to, subject, text: body });
    return true;
  } catch (err) {
    console.error('resend send failed', err);
    return false;
  }
}

export default async function handler(req, res) {
  if (req.headers.authorization !== `Bearer ${process.env.CRON_SECRET}`) {
    return res.status(401).json({ error: 'Unauthorized' });
  }

  const now = new Date();
  const results = { autoCheckout: 0, afterAbsence: 0, beforeEvent: 0, errors: [] };

  try {
    await runAutoCheckout(now, results);
    await runScheduledNotifications(now, results);
  } catch (err) {
    console.error(err);
    results.errors.push(err.message);
  }

  return res.status(200).json(results);
}

// event_date/start_time/end_time have no timezone column (matching the
// rest of the schema) — treated as server-local (UTC on Vercel), same
// simplification the rest of this app makes everywhere else.
async function runAutoCheckout(now, results) {
  const yesterday = new Date(now.getTime() - 24 * 3600000).toISOString().slice(0, 10);
  const today = now.toISOString().slice(0, 10);
  const { data: events, error } = await supabase
    .from('events')
    .select('id, event_date, end_time')
    .gte('event_date', yesterday)
    .lte('event_date', today)
    .not('end_time', 'is', null);
  if (error) { results.errors.push('autoCheckout events: ' + error.message); return; }

  for (const ev of events || []) {
    const [h, m] = ev.end_time.split(':').map(Number);
    const endDt = new Date(ev.event_date + 'T00:00:00');
    endDt.setHours(h, m, 0, 0);
    if (endDt > now) continue;

    const { data: rows, error: attErr } = await supabase
      .from('attendance').select('id')
      .eq('event_id', ev.id).not('checkin_at', 'is', null).is('checkout_at', null);
    if (attErr) { results.errors.push('autoCheckout attendance: ' + attErr.message); continue; }
    if (!rows || !rows.length) continue;

    const { error: updErr } = await supabase.from('attendance')
      .update({ checkout_at: endDt.toISOString(), auto_checkout: true })
      .in('id', rows.map(r => r.id));
    if (updErr) { results.errors.push('autoCheckout update: ' + updErr.message); continue; }
    results.autoCheckout += rows.length;
  }
}

async function runScheduledNotifications(now, results) {
  const { data: rules, error } = await supabase
    .from('notification_rules').select('*')
    .eq('enabled', true).in('trigger', ['after_absence', 'before_event']);
  if (error) { results.errors.push('rules: ' + error.message); return; }

  for (const rule of rules || []) {
    if (rule.trigger === 'after_absence') await handleAfterAbsenceRule(rule, results);
    else if (rule.trigger === 'before_event') await handleBeforeEventRule(rule, now, results);
  }
}

async function handleAfterAbsenceRule(rule, results) {
  const { data: tplRow } = await supabase.from('email_templates').select('*')
    .eq('ensemble_id', rule.ensemble_id).eq('key', rule.template_key).maybeSingle();
  if (!tplRow) return; // template was never saved for this ensemble — nothing to send

  const [{ data: policy }, { data: members, error: mErr }, { data: absences, error: aErr }, { data: ensemble }] = await Promise.all([
    supabase.from('grading_policies').select('*').eq('ensemble_id', rule.ensemble_id).maybeSingle(),
    supabase.from('ensemble_members').select('user_id, name, email')
      .eq('ensemble_id', rule.ensemble_id).eq('role', 'student').eq('status', 'active').not('user_id', 'is', null),
    supabase.from('attendance').select('user_id').eq('ensemble_id', rule.ensemble_id).eq('status', 'absent'),
    supabase.from('ensembles').select('*').eq('id', rule.ensemble_id).maybeSingle(),
  ]);
  if (mErr || aErr) { results.errors.push('after_absence: ' + (mErr || aErr).message); return; }

  const freeAbsences = policy?.free_absences ?? 2;
  const failThreshold = policy?.fail_threshold ?? 4;
  const threshold = rule.template_key === 'failing' ? failThreshold : freeAbsences + 1;

  const countByUser = {};
  (absences || []).forEach(a => { countByUser[a.user_id] = (countByUser[a.user_id] || 0) + 1; });

  for (const m of members || []) {
    const count = countByUser[m.user_id] || 0;
    if (count < threshold) continue;

    const { data: already } = await supabase.from('notification_log').select('id')
      .eq('rule_id', rule.id).eq('user_id', m.user_id).is('event_id', null).maybeSingle();
    if (already) continue;

    if (m.email) {
      const values = {
        '{{student_name}}': m.name || '', '{{absence_count}}': String(count),
        '{{absences_remaining}}': String(Math.max(0, failThreshold - count)),
        '{{production_name}}': ensemble?.name || '', '{{teacher_name}}': ensemble?.teacher_name || '',
        '{{teacher_email}}': ensemble?.teacher_email || '',
      };
      const ok = await sendMail(m.email, renderTokens(tplRow.subject, values), renderTokens(tplRow.body, values));
      if (ok) results.afterAbsence++;
    }
    await supabase.from('notification_log').insert({
      ensemble_id: rule.ensemble_id, user_id: m.user_id, rule_id: rule.id, event_id: null,
    });
  }
}

async function handleBeforeEventRule(rule, now, results) {
  const { data: tplRow } = await supabase.from('email_templates').select('*')
    .eq('ensemble_id', rule.ensemble_id).eq('key', rule.template_key).maybeSingle();
  if (!tplRow) return;

  const today = now.toISOString().slice(0, 10);
  const [{ data: events, error }, { data: members }, { data: ensemble }] = await Promise.all([
    supabase.from('events').select('*').eq('ensemble_id', rule.ensemble_id).gte('event_date', today),
    supabase.from('ensemble_members').select('user_id, name, email')
      .eq('ensemble_id', rule.ensemble_id).eq('role', 'student').eq('status', 'active').not('user_id', 'is', null),
    supabase.from('ensembles').select('*').eq('id', rule.ensemble_id).maybeSingle(),
  ]);
  if (error) { results.errors.push('before_event events: ' + error.message); return; }

  const offsetMs = (rule.offset_value || 0) * (rule.offset_unit === 'hr' ? 3600000 : 60000);

  for (const ev of events || []) {
    if (!ev.start_time) continue;
    const [h, m] = ev.start_time.split(':').map(Number);
    const startDt = new Date(ev.event_date + 'T00:00:00');
    startDt.setHours(h, m, 0, 0);
    const fireAt = new Date(startDt.getTime() - offsetMs);
    if (now < fireAt || now >= startDt) continue; // not time yet, or already started

    for (const mem of members || []) {
      const { data: already } = await supabase.from('notification_log').select('id')
        .eq('rule_id', rule.id).eq('user_id', mem.user_id).eq('event_id', ev.id).maybeSingle();
      if (already) continue;

      if (mem.email) {
        const values = {
          '{{student_name}}': mem.name || '', '{{event_name}}': ev.name || '',
          '{{event_date}}': ev.event_date || '', '{{production_name}}': ensemble?.name || '',
          '{{teacher_name}}': ensemble?.teacher_name || '', '{{teacher_email}}': ensemble?.teacher_email || '',
        };
        const ok = await sendMail(mem.email, renderTokens(tplRow.subject, values), renderTokens(tplRow.body, values));
        if (ok) results.beforeEvent++;
      }
      await supabase.from('notification_log').insert({
        ensemble_id: rule.ensemble_id, user_id: mem.user_id, rule_id: rule.id, event_id: ev.id,
      });
    }
  }
}
