-- Task 658: the reply box on the feedback triage form (template 27).
-- APPLY ONLY AFTER the support-app /api/dml change (task/658) is deployed: the server strips reply_body and
-- email_reply before the generic save. On an older server every Save on this form fails with
-- 'column "reply_body" of relation "feedback" does not exist' (happened live 2026-10-25).
-- The email goes out only when email_reply is checked AND Save is pressed.

UPDATE support.html_templates
SET html = replace(html,
      E'  {{/if}}\n{{/each}}',
      E'  {{/if}}\n  <div class="form-row">\n    <div class="form-field form-field-textarea">\n      <label for="reply_body">Reply to {{user_name}}</label>\n      <textarea id="reply_body" name="reply_body" rows="5" placeholder="Write a reply. It is emailed only when the box below is checked and you press Save."></textarea>\n    </div>\n  </div>\n  <div class="form-row">\n    <div class="form-field">\n      <label for="email_reply">\n        <input type="hidden" name="email_reply" value="false" />\n        <input type="checkbox" id="email_reply" name="email_reply" value="true" />\n        Email this reply on Save\n      </label>\n    </div>\n  </div>\n{{/each}}')
WHERE name = 'feedback_triage_form' AND html NOT LIKE '%name="reply_body"%';
