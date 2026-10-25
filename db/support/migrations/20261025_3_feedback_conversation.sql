-- Task 659: feedback conversation. Inbound mail is stored in feedback_replies (direction 'in'), de-duplicated on
-- the mail's Message-ID, and the triage form shows the whole thread oldest-first as expandable rows.

ALTER TABLE support.feedback_replies
  ADD COLUMN IF NOT EXISTS from_email text,
  ADD COLUMN IF NOT EXISTS message_id text;

CREATE UNIQUE INDEX IF NOT EXISTS feedback_replies_message_id_uq
  ON support.feedback_replies (message_id) WHERE message_id IS NOT NULL;

-- Form data: the thread, oldest first, times shown in Central (sent_at is stored UTC).
UPDATE support.html_templates
SET hydrate = regexp_replace(hydrate,
      '\(select coalesce\(jsonb_agg\(.*?\) as replies',
      $h$(select coalesce(jsonb_agg(jsonb_build_object(
        'when', to_char((r.sent_at AT TIME ZONE 'UTC') AT TIME ZONE 'America/Chicago', 'Mon DD, HH12:MI AM'),
        'who', case when r.direction = 'out' then 'You' else coalesce(r.from_email, 'User') end,
        'summary', left(regexp_replace(r.body, '\s+', ' ', 'g'), 90),
        'body', r.body) order by r.id), '[]'::jsonb)
      from support.feedback_replies r where r.feedback_id = f.id) as replies$h$)
WHERE name = 'feedback_triage_form' AND hydrate NOT LIKE '%''summary''%';

-- Form markup: replace the plain "Replies sent" list with an expandable conversation grid (no JS, CSP-safe).
UPDATE support.html_templates
SET html = regexp_replace(html,
      '  \{\{#if has_replies\}\}.*?  \{\{/if\}\}\n',
      $m$  {{#if has_replies}}
  <div class="form-row">
    <div class="form-field form-field-textarea">
      <label>Conversation ({{reply_count}})</label>
      <div style="max-height: 280px; overflow: auto; border: 1px solid #cdd; border-radius: 6px;">
        {{#each replies}}
        <details style="border-bottom: 1px solid #e3e8ea; padding: 4px 8px;">
          <summary style="cursor: pointer; display: grid; grid-template-columns: 9em 9em 1fr; gap: 8px;"><span>{{when}}</span><strong>{{who}}</strong><span>{{summary}}</span></summary>
          <div style="white-space: pre-wrap; padding: 6px 0 2px 0;">{{body}}</div>
        </details>
        {{/each}}
      </div>
    </div>
  </div>
  {{/if}}
$m$)
WHERE name = 'feedback_triage_form' AND html NOT LIKE '%Conversation (%';
