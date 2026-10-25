-- Task 659: an expanded conversation row showed its message twice (summary line + full text).
-- When a row is open, hide the summary's text; closed rows keep their one-line summary.

UPDATE support.html_templates
SET html = replace(html,
      '<div style="max-height: 280px; overflow: auto; border: 1px solid #cdd; border-radius: 6px;">',
      '<style>.convo details[open] > summary > span:last-child { visibility: hidden; height: 0; overflow: hidden; }</style>
      <div class="convo" style="max-height: 280px; overflow: auto; border: 1px solid #cdd; border-radius: 6px;">')
WHERE name = 'feedback_triage_form' AND html NOT LIKE '%class="convo"%';
