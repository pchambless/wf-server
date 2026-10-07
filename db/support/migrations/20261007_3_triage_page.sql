-- 2026-10-07 task 477, step 3: support-app Feedback triage page (templates, page, components, menu)
SET ROLE wf_admin;
BEGIN;

INSERT INTO support.html_templates (name, platform, title, css, hydrate, html, created_by) VALUES
('feedback_status_dd', 'dropdown', 'Status', '{}',
$h$select
  (:status::text = 'All' OR :status::text IS NULL) as is_all,
  :status::text = 'new' as is_new,
  :status::text = 'reviewing' as is_reviewing,
  :status::text = 'planned' as is_planned,
  :status::text = 'done' as is_done,
  :status::text = 'declined' as is_declined$h$,
$h$<select name="status">
  {{#each data}}
  <option value="All" {{#if is_all}}selected{{/if}}>All</option>
  <option value="new" {{#if is_new}}selected{{/if}}>New</option>
  <option value="reviewing" {{#if is_reviewing}}selected{{/if}}>Reviewing</option>
  <option value="planned" {{#if is_planned}}selected{{/if}}>Planned</option>
  <option value="done" {{#if is_done}}selected{{/if}}>Done</option>
  <option value="declined" {{#if is_declined}}selected{{/if}}>Declined</option>
  {{/each}}
</select>$h$, 'claude'),

('feedback_grid', 'grid', 'Feedback', '{page-grid}',
$h$select id,
  to_char(created_at, 'YYYY-MM-DD') as submitted,
  source_env,
  coalesce(user_name, email) as from_user,
  account_name,
  page_name,
  category,
  title,
  status,
  task_id,
  CASE status WHEN 'new' THEN '#b45309' WHEN 'done' THEN '#16a34a' WHEN 'declined' THEN '#6b7280' ELSE '#1d4ed8' END as status_color
from support.vw_feedback
where (:status::text = 'All' OR :status::text IS NULL OR status = :status::text)
order by created_at desc, id desc
limit 200$h$,
$h$<div class="table page-grid grid-fixed grid-scroll grid-sticky">
  <table>
    <colgroup>
      <col style="width:9%;">
      <col style="width:6%;">
      <col style="width:17%;">
      <col style="width:10%;">
      <col style="width:8%;">
      <col style="width:26%;">
      <col style="width:10%;">
      <col style="width:6%;">
    </colgroup>
    <thead>
      <tr>
        <th>Date</th>
        <th>Env</th>
        <th>From</th>
        <th>Page</th>
        <th>Type</th>
        <th>Title</th>
        <th>Status</th>
        <th>Task</th>
      </tr>
    </thead>
    <tbody>
      {{#each data}}
      <tr class="grid-row" data-row-id="{{id}}">
        <td>{{submitted}}</td>
        <td>{{source_env}}</td>
        <td>{{from_user}} <span style="color:#6b7280;">({{account_name}})</span></td>
        <td>{{page_name}}</td>
        <td>{{category}}</td>
        <td>{{title}}</td>
        <td style="color: {{status_color}}">{{status}}</td>
        <td>{{task_id}}</td>
      </tr>
      {{/each}}
    </tbody>
  </table>
</div>$h$, 'claude'),

('feedback_triage_form', 'form', 'Feedback', '{form}',
$h$select f.*,
  f.status = 'new' as is_new,
  f.status = 'reviewing' as is_reviewing,
  f.status = 'planned' as is_planned,
  f.status = 'done' as is_done,
  f.status = 'declined' as is_declined
from support.vw_feedback f
where f.id = :id$h$,
$h$<form class="form-container">
{{#each data}}
  <input type="hidden" name="record_id" value="{{id}}" />
  <div class="form-row">
    <div class="form-field form-field-text">
      <label>Title</label>
      <div data-header-field="true"><strong>{{title}}</strong></div>
    </div>
  </div>
  <div class="form-row">
    <div class="form-field"><label>From</label><div>{{user_name}} &lt;{{email}}&gt;</div></div>
    <div class="form-field"><label>Account</label><div>{{account_name}} (id {{account_id}})</div></div>
  </div>
  <div class="form-row">
    <div class="form-field"><label>Page</label><div>{{page_name}}</div></div>
    <div class="form-field"><label>Type</label><div>{{category}}</div></div>
    <div class="form-field"><label>Environment</label><div>{{source_env}}</div></div>
  </div>
  <div class="form-row">
    <div class="form-field form-field-textarea">
      <label>Message</label>
      <div style="white-space: pre-wrap;">{{message}}</div>
    </div>
  </div>
  <div class="form-row">
    <div class="form-field">
      <label for="status">Status</label>
      <select id="status" name="status">
        <option value="new" {{#if is_new}}selected{{/if}}>New</option>
        <option value="reviewing" {{#if is_reviewing}}selected{{/if}}>Reviewing</option>
        <option value="planned" {{#if is_planned}}selected{{/if}}>Planned</option>
        <option value="done" {{#if is_done}}selected{{/if}}>Done</option>
        <option value="declined" {{#if is_declined}}selected{{/if}}>Declined</option>
      </select>
    </div>
    <div class="form-field">
      <label for="task_id">Task # (agile board)</label>
      <input type="number" id="task_id" name="task_id" value="{{task_id}}" min="1" />
    </div>
  </div>
{{/each}}
</form>$h$, 'claude');

INSERT INTO support.pages (page_name, group_name, template_id, table_name, table_id, form_template, grid_template,
                           context_key, page_title, form_head_col, table_config, data)
VALUES ('feedback', 'feedback', 12, 'support.feedback', 'id', 'feedback_triage_form', 'feedback-grid',
        'feedback_id', 'Feedback', 'title', '{}'::jsonb, '{}'::jsonb);

INSERT INTO support.page_components (page_id, comp_name, slot_name, ordr, actions, html_template_id)
SELECT p.id, 'feedback-grid', 'grid', 1,
       '{"row_click": [{"action": "open_inline_form", "values": {"id": "{{id}}", "mode": "UPDATE", "feedback_id": "{{id}}"}, "form_template": "feedback_triage_form"}]}'::jsonb,
       (SELECT id FROM support.html_templates WHERE name = 'feedback_grid')
  FROM support.pages p WHERE p.page_name = 'feedback';

INSERT INTO support.page_components (page_id, comp_name, slot_name, ordr, actions, html_template_id)
SELECT p.id, 'feedback-status-dd', 'dropdown-1', 1,
       '{"select_change": {"action": "setVals", "values": {"status": "{{value}}"}, "refresh": ["feedback-grid"]}}'::jsonb,
       (SELECT id FROM support.html_templates WHERE name = 'feedback_status_dd')
  FROM support.pages p WHERE p.page_name = 'feedback';

WITH g AS (
  INSERT INTO support.action_groups (group_name, page_id, slot_name, render_as, ordr)
  VALUES ('Feedback', 1, 'appbar', 'menu', 3) RETURNING id
)
INSERT INTO support.action_components (group_id, component_name, label, action_type, ordr, actions, visible_when)
SELECT g.id, 'feedback', 'Feedback', 'redirect', 1, '{"css": "agile-bg", "url": "/feedback"}'::jsonb, '{}'::jsonb FROM g;

COMMIT;
SELECT p.id AS page_id, count(pc.id) AS comps FROM support.pages p LEFT JOIN support.page_components pc ON pc.page_id = p.id WHERE p.page_name = 'feedback' GROUP BY p.id;
