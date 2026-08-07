// Shared Gmail SMTP sender for api/send-email.js and api/cron/tick.js.
//
// Gmail SMTP won't reliably deliver on behalf of an arbitrary From address
// (it either rejects it or silently rewrites it to the authenticated
// account unless that address is configured as a Gmail "Send As" alias) —
// so this always sends as GMAIL_USER itself, no per-call override.
import nodemailer from 'nodemailer';

const transporter = nodemailer.createTransport({
  service: 'gmail',
  auth: { user: process.env.GMAIL_USER, pass: process.env.GMAIL_APP_PASSWORD },
});

export async function sendMail(to, subject, text) {
  try {
    await transporter.sendMail({
      from: `Call Time <${process.env.GMAIL_USER}>`,
      to, subject, text,
    });
    return true;
  } catch (err) {
    console.error('gmail send failed', err);
    return false;
  }
}
