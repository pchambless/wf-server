-- Task 676: the Targeted column only needs the date's width. It shows the target date (the release name stays in the
-- hover title); a release with no date shows its name. Title takes the freed width.

UPDATE support.html_templates
SET html = replace(replace(html,
      E'<col style="width:44%;">\n      <col style="width:10%;">\n      <col style="width:8%;">\n      <col style="width:14%;">',
      E'<col style="width:48%;">\n      <col style="width:10%;">\n      <col style="width:8%;">\n      <col style="width:10%;">'),
      '{{#if target_release}}{{target_release}}{{/if}}{{#if target_when}} <span style="color:#6b7280;">{{target_when}}</span>{{/if}}</td>',
      '{{#if target_when}}{{target_when}}{{else}}{{target_release}}{{/if}}</td>')
WHERE id = 2 AND html LIKE '%{{#if target_release}}{{target_release}}{{/if}}%';
