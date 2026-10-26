-- Task 681: release-specific form. A release is a Sprint under the release epic (agile.f_release_epic_id()). For a release the
-- agile form hides Parent and Page Type, labels the description Goal, and shows derived State / Progress / Shipped from
-- agile.vw_release_state (wf-agents adhoc/migrations/task_release_state_view.sql). Topical sprints, epics and tasks are unchanged.

UPDATE support.html_templates
SET hydrate = replace(replace(hydrate,
$ho0$select *,
$ho0$,
$hn0$select v.*,
$hn0$),
$ho1$as releases
from agile.vw_agile_cache v
where v.id = :id$ho1$,
$hn1$as releases,
  (v.page_type = 'Sprint' and v.parent_id = agile.f_release_epic_id()) as is_release,
  rs.state as release_state,
  rs.done_count as release_done,
  rs.total_count as release_total,
  to_char(rs.shipped_on, 'YYYY-MM-DD') as shipped_on_s
from agile.vw_agile_cache v
left join agile.vw_release_state rs on rs.id = v.id
where v.id = :id$hn1$),
    html = replace(replace(replace(replace(html,
$to0$    <div class="form-field">
      <label for="page_type">Page Type</label>
      <select id="page_type" name="page_type">
        <option value="Task" {{#if is_type_task}}selected{{/if}}>Task</option>
        <option value="Sprint" {{#if is_type_sprint}}selected{{/if}}>Sprint</option>
        <option value="Epic" {{#if is_type_epic}}selected{{/if}}>Epic</option>
        <option value="App" {{#if is_type_app}}selected{{/if}}>App</option>
      </select>
    </div>
$to0$,
$tn0$    {{#unless is_release}}
    <div class="form-field">
      <label for="page_type">Page Type</label>
      <select id="page_type" name="page_type">
        <option value="Task" {{#if is_type_task}}selected{{/if}}>Task</option>
        <option value="Sprint" {{#if is_type_sprint}}selected{{/if}}>Sprint</option>
        <option value="Epic" {{#if is_type_epic}}selected{{/if}}>Epic</option>
        <option value="App" {{#if is_type_app}}selected{{/if}}>App</option>
      </select>
    </div>
    {{/unless}}
$tn0$),
$to1$  <div class="form-row">
    <div class="form-field">
      <label for="parent_id">Parent</label>
      <div data-embed-dropdown="agile_parent_dd" data-embed-field="parent_id" data-embed-value="{{parent_id}}"></div>
    </div>
  </div>
$to1$,
$tn1$  {{#unless is_release}}
  <div class="form-row">
    <div class="form-field">
      <label for="parent_id">Parent</label>
      <div data-embed-dropdown="agile_parent_dd" data-embed-field="parent_id" data-embed-value="{{parent_id}}"></div>
    </div>
  </div>
  {{/unless}}
$tn1$),
$to2$  {{#if is_type_sprint}}
  <div class="form-row">
    <div class="form-field">
      <label for="target_date">Target date</label>
      <input type="date" id="target_date" name="target_date" value="{{target_date_s}}" />
    </div>
  </div>
  {{/if}}
$to2$,
$tn2$  {{#if is_type_sprint}}
  <div class="form-row">
    <div class="form-field">
      <label for="target_date">Target date</label>
      <input type="date" id="target_date" name="target_date" value="{{target_date_s}}" />
    </div>
  </div>
  {{/if}}
  {{#if is_release}}
  <div class="form-row">
    <div class="form-field"><label>State</label><div>{{release_state}}</div></div>
    <div class="form-field"><label>Progress</label><div>{{release_done}} of {{release_total}} tasks done</div></div>
    {{#if shipped_on_s}}<div class="form-field"><label>Shipped</label><div>{{shipped_on_s}}</div></div>{{/if}}
  </div>
  {{/if}}
$tn2$),
$to3$<label for="description">Description</label>$to3$,
$tn3$<label for="description">{{#if is_release}}Goal{{else}}Description{{/if}}</label>$tn3$)
WHERE id = 5 AND hydrate NOT LIKE '%is_release%';
