// Vercel serverless function — Call Time Phase 3 (spec §3.2).
//
// The spec's example handler takes { to, subject, body, from } with no
// auth at all, which would make this a public email relay the moment it's
// deployed (anyone who finds the URL could spam through your Gmail
// account). This adds one check beyond the spec: the caller must present
// a valid Supabase session token. It does NOT verify the caller is
// actually allowed to email `to` specifically (e.g. a teacher of that
// student's ensemble) — that would need a service-role Supabase client to
// check ensemble_members server-side. Worth adding before this handles
// real student data at scale; out of scope for getting email sending
// working.
import { createClient } from '@supabase/supabase-js';
import { sendMail } from './_mailer.js';

const supabase = createClient(process.env.SUPABASE_URL, process.env.SUPABASE_ANON_KEY);

export default async function handler(req, res) {
  if (req.method !== 'POST') {
    return res.status(405).json({ error: 'Method not allowed' });
  }

  const authHeader = req.headers.authorization || '';
  const token = authHeader.startsWith('Bearer ') ? authHeader.slice(7) : null;
  if (!token) return res.status(401).json({ error: 'Missing Authorization header' });

  const { data: userData, error: authError } = await supabase.auth.getUser(token);
  if (authError || !userData?.user) {
    return res.status(401).json({ error: 'Invalid or expired session' });
  }

  const { to, subject, body } = req.body || {};
  if (!to || !subject || !body) {
    return res.status(400).json({ error: 'to, subject, and body are required' });
  }

  const ok = await sendMail(to, subject, body);
  if (!ok) return res.status(400).json({ error: 'Send failed — check GMAIL_USER/GMAIL_APP_PASSWORD.' });
  return res.status(200).json({ data: { to, subject } });
}
