-- Task 668: Release picker on the agile task form. The hydrate lists the planned releases (the Sprints under the release
-- epic, agile.f_release_epic_id(), wf-agents adhoc/migrations/task668_release_epic_fn.sql) with the current one marked;
-- the form shows Release + Target date for Tasks and Target date for Sprints (a release sprint carries its own date).
-- Additive: no existing field is touched. target_release_id / target_date are columns of agile.agile_cache (task 667).

UPDATE support.html_templates
SET hydrate = replace(hydrate,
$h1$  jsonb_array_length(coalesce(notes, '[]'::jsonb)) > 0 as has_notes
from agile.vw_agile_cache
where id = :id$h1$,
$h2$  jsonb_array_length(coalesce(notes, '[]'::jsonb)) > 0 as has_notes,
  to_char(target_date, 'YYYY-MM-DD') as target_date_s,
  (select coalesce(jsonb_agg(jsonb_build_object('id', r.id, 'name', r.page_name, 'selected', r.id = v.target_release_id) order by r.id), '[]'::jsonb)
     from agile.vw_agile_cache r
    where r.parent_id = agile.f_release_epic_id() and r.page_type = 'Sprint') as releases
from agile.vw_agile_cache v
where v.id = :id$h2$),
    html = replace(html,
$a$  <div class="form-row">
    <div class="form-field form-field-textarea">
      <label for="description">Description</label>$a$,
$b$  {{#if is_type_task}}
  <div class="form-row">
    <div class="form-field">
      <label for="target_release_id">Release</label>
      <select id="target_release_id" name="target_release_id">
        <option value="" {{#unless target_release_id}}selected{{/unless}}>- (not planned)</option>
        {{#each releases}}
        <option value="{{id}}" {{#if selected}}selected{{/if}}>{{name}}</option>
        {{/each}}
      </select>
    </div>
    <div class="form-field">
      <label for="target_date">Target date</label>
      <input type="date" id="target_date" name="target_date" value="{{target_date_s}}" />
    </div>
  </div>
  {{/if}}
  {{#if is_type_sprint}}
  <div class="form-row">
    <div class="form-field">
      <label for="target_date">Target date</label>
      <input type="date" id="target_date" name="target_date" value="{{target_date_s}}" />
    </div>
  </div>
  {{/if}}
  <div class="form-row">
    <div class="form-field form-field-textarea">
      <label for="description">Description</label>$b$)
WHERE id = 5 AND hydrate NOT LIKE '%f_release_epic_id%';
