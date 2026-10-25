-- Task 658: reply to feedback by email from the triage form.
-- support is a dev-only schema, so this file is its only record (git).

-- 1. One row per message sent (direction 'out') or, later, captured (direction 'in').
CREATE TABLE IF NOT EXISTS support.feedback_replies (
  id          serial PRIMARY KEY,
  feedback_id integer   NOT NULL REFERENCES support.feedback(id),
  direction   text      NOT NULL DEFAULT 'out' CHECK (direction IN ('out', 'in')),
  to_email    text,
  subject     text,
  body        text      NOT NULL,
  sent_by     text,
  sent_at     timestamp NOT NULL DEFAULT now(),
  result      text      NOT NULL DEFAULT 'sent'
);
CREATE INDEX IF NOT EXISTS feedback_replies_feedback_idx ON support.feedback_replies (feedback_id, id);

-- 2. Triage form (template 27): 'replied' status and the replies already sent.
--    The reply box itself is 20261025_2 and must go in only AFTER the support-app change is deployed:
--    the deployed server strips reply_body/email_reply; an older server passes them to the generic save and fails (found 2026-10-25).
UPDATE support.html_templates
SET hydrate = replace(hydrate,
      E'f.status = ''declined'' as is_declined',
      E'f.status = ''declined'' as is_declined,\n  f.status = ''replied'' as is_replied,\n  exists (select 1 from support.feedback_replies r where r.feedback_id = f.id) as has_replies,\n  (select count(*)::text from support.feedback_replies r where r.feedback_id = f.id) as reply_count,\n  (select coalesce(jsonb_agg(jsonb_build_object(''sent_at'', to_char(r.sent_at, ''Mon DD, HH12:MI AM''), ''to_email'', r.to_email, ''body'', r.body) order by r.id desc), ''[]''::jsonb) from support.feedback_replies r where r.feedback_id = f.id) as replies'),
    html = replace(replace(html,
      E'<option value="declined"',
      E'<option value="replied" {{#if is_replied}}selected{{/if}}>Replied</option>\n        <option value="declined"'),
      E'{{/each}}',
      E'  {{#if has_replies}}\n  <div class="form-row">\n    <div class="form-field form-field-textarea">\n      <label>Replies sent ({{reply_count}})</label>\n      {{#each replies}}\n      <div style="white-space: pre-wrap; border-left: 3px solid #9bc; padding-left: 8px; margin-bottom: 6px;"><small>{{sent_at}} to {{to_email}}</small><br>{{body}}</div>\n      {{/each}}\n    </div>\n  </div>\n  {{/if}}\n{{/each}}')
WHERE name = 'feedback_triage_form' AND hydrate NOT LIKE '%is_replied%';

-- 3. Status filter dropdown (template 25): add Replied.
UPDATE support.html_templates
SET hydrate = replace(hydrate,
      E':status::text = ''declined'' as is_declined',
      E':status::text = ''declined'' as is_declined,\n  :status::text = ''replied'' as is_replied'),
    html = replace(html,
      E'<option value="declined"',
      E'<option value="replied" {{#if is_replied}}selected{{/if}}>Replied</option>\n  <option value="declined"')
WHERE name = 'feedback_status_dd' AND hydrate NOT LIKE '%is_replied%';
