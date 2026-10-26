-- Task 681: Target date on a Sprint only makes sense for a planned release; topical sprints no longer show it.
-- (Tasks keep Release + Target date from 20261025_14.)

UPDATE support.html_templates
SET html = replace(html,
$o${{#if is_type_sprint}}
  <div class="form-row">
    <div class="form-field">
      <label for="target_date">Target date</label>$o$,
$n${{#if is_release}}
  <div class="form-row">
    <div class="form-field">
      <label for="target_date">Target date</label>$n$)
WHERE id = 5 AND html LIKE '%{{#if is_type_sprint}}%';
