-- Task 676 (board layout): half the hierarchy indent, narrower Status/Priority/Deployed, and a Targeted column for
-- the planning layer (agile_cache.target_release_id + target_date). Targeted shows the planned release's name and
-- its target date (the task's own target_date wins over the release's). Empty until work is targeted.

UPDATE support.html_templates
SET hydrate = replace(replace(hydrate,
      '(level - 1) * 20 as indent_px',
      '(level - 1) * 10 as indent_px'),
      'agile.f_feedback_ids(f.id, f.page_type) as feedback_ids',
      E'agile.f_feedback_ids(f.id, f.page_type) as feedback_ids,\n(select r.page_name from agile.agile_cache a join agile.agile_cache r on r.id = a.target_release_id where a.id = f.id) as target_release,\n(select to_char(coalesce(a.target_date, r.target_date), ''YYYY-MM-DD'') from agile.agile_cache a left join agile.agile_cache r on r.id = a.target_release_id where a.id = f.id) as target_when'),
    html = replace(replace(replace(html,
      E'<col style="width:38%;">\n      <col style="width:14%;">\n      <col style="width:12%;">\n      <col style="width:14%;">\n      <col style="width:8%;">',
      E'<col style="width:44%;">\n      <col style="width:10%;">\n      <col style="width:8%;">\n      <col style="width:14%;">\n      <col style="width:12%;">\n      <col style="width:8%;">'),
      '<th>Priority</th>',
      E'<th>Priority</th>\n        <th title="Release this work is planned for, and its target date">Targeted</th>'),
      '<td style="color: {{priority_color}}">{{priority}}</td>',
      E'<td style="color: {{priority_color}}">{{priority}}</td>\n        <td{{#if target_release}} title="{{target_release}}"{{/if}}>{{#if target_release}}{{target_release}}{{/if}}{{#if target_when}} <span style="color:#6b7280;">{{target_when}}</span>{{/if}}</td>')
WHERE id = 2 AND html NOT LIKE '%>Targeted<%';
