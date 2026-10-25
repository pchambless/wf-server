import { callWorkflow } from './n8nClient.js';
import logger from './logger.js';

// Signup emails (task 663). Fire-and-forget: a mail problem must never break or slow a registration, so the
// caller does not await this and every failure is only logged. Plain text only; no password or other secret
// is ever put in either message.
const ALERT_RECIPIENTS = (process.env.SIGNUP_ALERT_RECIPIENTS || 'pc7900@gmail.com,joel@twomenandagarden.com')
  .split(',')
  .map((a) => a.trim())
  .filter(Boolean);

const oneLine = (v) => String(v || '').replace(/\s+/g, ' ').trim();

export function sendSignupEmails({ first_name, last_name, email, company_name, zip_code, account_id, user_id }) {
  const first = oneLine(first_name);
  const company = oneLine(company_name);

  const welcome = {
    to: email,
    subject: 'Welcome to WhatsFresh',
    text: [
      `Hi ${first},`,
      '',
      `Your WhatsFresh account for ${company} is ready. Sign in any time at https://v2.whatsfresh.app/login with the email you registered with.`,
      '',
      "A few things to know: pricing is $30 a month or $300 a year, and we'll be in touch about billing. If anything is confusing or missing, use the Feedback button in the app. It comes straight to us and we answer it.",
      '',
      'Thanks for trying WhatsFresh.',
      'Paul'
    ].join('\n'),
    reply_to: 'pc7900@gmail.com'
  };

  const alertText = [
    'New WhatsFresh signup',
    '',
    `Name: ${oneLine(first_name)} ${oneLine(last_name)}`,
    `Company: ${company}`,
    `Email: ${oneLine(email)}`,
    `Zip: ${oneLine(zip_code)}`,
    `Account id: ${account_id}   User id: ${user_id}`,
    '',
    'Joel: please create a Stripe customer and subscription for this account ($30/month or $300/year). When it exists,',
    `tell Paul the Stripe customer id so it can be recorded on account ${account_id}.`
  ].join('\n');

  const messages = [
    { label: 'welcome', body: welcome },
    ...ALERT_RECIPIENTS.map((to) => ({
      label: 'alert',
      body: { to, subject: `New WhatsFresh signup: ${company}`, text: alertText }
    }))
  ];

  return Promise.allSettled(
    messages.map(async ({ label, body }) => {
      try {
        const res = await callWorkflow('send-email', body);
        if (!res || res.success !== true) throw new Error(res?.error || 'send-email did not report success');
        logger.info('[signup-email] sent', { label, account_id });
      } catch (err) {
        logger.warn('[signup-email] failed', { label, account_id, error: err.message });
      }
    })
  );
}
