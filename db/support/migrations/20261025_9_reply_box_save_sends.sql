-- Task 659: Save sends the reply whenever the reply box has text, so the "Email this reply on Save" checkbox goes
-- and a one-line hint sits under the box. APPLY ONLY AFTER the support-app change (task/659-save-sends-reply) is
-- deployed; the new server also works with the old form, so deploying first is always safe.

UPDATE support.html_templates
SET html = replace(replace(html,
$a$      <textarea id="reply_body" name="reply_body" rows="5" placeholder="Write a reply. It is emailed only when the box below is checked and you press Save."></textarea>
$a$,
$b$      <textarea id="reply_body" name="reply_body" rows="5" placeholder="Write a reply."></textarea>
      <div style="font-size: 12px; color: #6b7280; margin-top: 2px;">Pressing Save sends this reply by email.</div>
$b$),
$c$  <div class="form-row">
    <div class="form-field">
      <label for="email_reply">
        <input type="hidden" name="email_reply" value="false" />
        <input type="checkbox" id="email_reply" name="email_reply" value="true" />
        Email this reply on Save
      </label>
    </div>
  </div>
$c$, '')
WHERE name = 'feedback_triage_form' AND html LIKE '%name="email_reply"%';
