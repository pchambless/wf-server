-- Task 659: the conversation starts with the user's own message (row 1, open by default), then the replies.
-- The separate Message field is removed from the form: it was the same text, now it is the first thread row.

UPDATE support.html_templates
SET hydrate = replace(replace(replace(hydrate,
      $a$(select coalesce(jsonb_agg($a$,
      $b$(select jsonb_build_array(jsonb_build_object(
          'when', to_char((f.created_at AT TIME ZONE 'UTC') AT TIME ZONE 'America/Chicago', 'Mon DD, HH12:MI AM'),
          'who', coalesce(f.user_name, f.email),
          'summary', left(regexp_replace(f.message, '\s+', ' ', 'g'), 90),
          'body', f.message)) || coalesce(jsonb_agg($b$),
      $c$exists (select 1 from support.feedback_replies r where r.feedback_id = f.id) as has_replies$c$,
      $d$true as has_replies$d$),
      $e$(select count(*)::text from support.feedback_replies r where r.feedback_id = f.id) as reply_count$e$,
      $f$((select count(*) from support.feedback_replies r where r.feedback_id = f.id) + 1)::text as reply_count$f$)
WHERE name = 'feedback_triage_form' AND hydrate NOT LIKE '%jsonb_build_array(%';

UPDATE support.html_templates
SET html = replace(replace(html,
      $g$  <div class="form-row">
    <div class="form-field form-field-textarea">
      <label>Message</label>
      <div style="white-space: pre-wrap;">{{message}}</div>
    </div>
  </div>
$g$, ''),
      '<details style=', '<details {{#if @first}}open{{/if}} style=')
WHERE name = 'feedback_triage_form' AND html NOT LIKE '%@first%';
