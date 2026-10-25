-- Task 676: mark agile work that came from feedback. The board grid shows a small "FB 14" tag after the title,
-- derived from agile.f_feedback_ids (support.feedback.task_id), rolled up to sprints and epics. Additive: one
-- hydrate column and one span; no column or width changes.

UPDATE support.html_templates
SET hydrate = replace(hydrate,
      '(select a.trello_card from agile.agile_cache a where a.id = f.id) as trello_card',
      E'(select a.trello_card from agile.agile_cache a where a.id = f.id) as trello_card,\nagile.f_feedback_ids(f.id, f.page_type) as feedback_ids'),
    html = replace(html,
      '{{title}} ({{done_count}}/{{total_count}})</td>',
      '{{title}} ({{done_count}}/{{total_count}}){{#if feedback_ids}} <span style="font-size:11px; color:#0f766e; border:1px solid #0f766e; border-radius:4px; padding:0 4px; margin-left:6px; white-space:nowrap;" title="Spawned by feedback">FB {{feedback_ids}}</span>{{/if}}</td>')
WHERE id = 2 AND hydrate NOT LIKE '%f_feedback_ids%';
