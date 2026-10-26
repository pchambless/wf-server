-- Task 681: rebalance the Releases report columns so headers do not wrap in a narrow modal (Task 7, Status 11, Priority 9).

UPDATE support.html_templates
SET html = replace(replace(replace(replace(replace(replace(replace(html,
      '<th style="width: 7%;">Task</th>', '<th style="width: 8%;">Task</th>'),
      '<th style="width: 34%;">Title</th>', '<th style="width: 29%;">Title</th>'),
      '<th style="width: 27%;">Sprint (Epic)</th>', '<th style="width: 24%;">Sprint (Epic)</th>'),
      '<th style="width: 9%;">Status</th>', '<th style="width: 12%;">Status</th>'),
      '<th style="width: 8%;">Priority</th>', '<th style="width: 10%;">Priority</th>'),
      '<th style="width: 7%;">From</th>', '<th style="width: 8%;">From</th>'),
      '<th style="width: 8%;">Deployed</th>', '<th style="width: 9%;">Deployed</th>')
WHERE name = 'rpt_agile_releases_body' AND html LIKE '%width: 34%%';
