-- Task 679: switch the grid search on the agile board to FIND mode (highlight, tint the match's descendants, step
-- through matches) instead of filtering. Opt-in per grid via data-search-mode="find". Apply only after the support-app
-- deploy that carries app-engine 8960fd2; the other grids are untouched.

UPDATE support.html_templates
SET html = replace(html,
      '<div class="table page-grid grid-fixed grid-scroll grid-sticky">',
      '<div class="table page-grid grid-fixed grid-scroll grid-sticky" data-search-mode="find">')
WHERE id = 2 AND html NOT LIKE '%data-search-mode%';
