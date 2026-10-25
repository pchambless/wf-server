-- Task 659: show the feedback number (the N in the [WhatsFresh #N] email tag) in the grid and in the form heading,
-- and give the new 'replied' status its own colour (it was the same blue as 'reviewing').

UPDATE support.html_templates
SET html = replace(replace(replace(html,
      E'<colgroup>\n', E'<colgroup>\n      <col style="width:4%;">\n'),
      E'<th>Date</th>', E'<th>#</th>\n        <th>Date</th>'),
      E'<td>{{submitted}}</td>', E'<td>{{id}}</td>\n        <td>{{submitted}}</td>'),
    hydrate = replace(hydrate,
      E'WHEN ''declined'' THEN ''#6b7280''',
      E'WHEN ''declined'' THEN ''#6b7280'' WHEN ''replied'' THEN ''#0f766e''')
WHERE name = 'feedback_grid' AND html NOT LIKE '%<th>#</th>%';

UPDATE support.html_templates
SET html = replace(html, E'<strong>{{title}}</strong>', E'<strong>#{{id}}: {{title}}</strong>')
WHERE name = 'feedback_triage_form' AND html NOT LIKE '%#{{id}}: {{title}}%';
