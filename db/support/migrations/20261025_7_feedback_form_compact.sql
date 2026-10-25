-- Task 659: tighten the triage form. The title is already in the panel header (built from the hidden
-- data-header-field element, which must stay), so the visible Title row goes; From/Account/Env share a line,
-- Page/Type the next.

UPDATE support.html_templates
SET html = replace(html,
$o$  <div class="form-row">
    <div class="form-field form-field-text">
      <label>Title</label>
      <div data-header-field="true"><strong>#{{id}}: {{title}}</strong></div>
    </div>
  </div>
  <div class="form-row">
    <div class="form-field"><label>From</label><div>{{user_name}} <!--email_off-->&lt;{{email}}&gt;<!--/email_off--></div></div>
    <div class="form-field"><label>Account</label><div>{{account_name}} (id {{account_id}})</div></div>
  </div>
  <div class="form-row">
    <div class="form-field"><label>Page</label><div>{{page_name}}</div></div>
    <div class="form-field"><label>Type</label><div>{{category}}</div></div>
    <div class="form-field"><label>Environment</label><div>{{source_env}}</div></div>
  </div>
$o$,
$n$  <div data-header-field="true" style="display:none;">#{{id}}: {{title}}</div>
  <div class="form-row">
    <div class="form-field" style="flex:1 1 100%; font-size:13px;">
      <div style="display:flex; flex-wrap:wrap; gap:2px 18px;">
        <span><label style="display:inline; margin-right:4px;">From</label>{{user_name}} <!--email_off-->&lt;{{email}}&gt;<!--/email_off--></span>
        <span><label style="display:inline; margin-right:4px;">Account</label>{{account_name}} (id {{account_id}})</span>
        <span><label style="display:inline; margin-right:4px;">Env</label>{{source_env}}</span>
      </div>
      <div style="display:flex; flex-wrap:wrap; gap:2px 18px; margin-top:2px;">
        <span><label style="display:inline; margin-right:4px;">Page</label>{{page_name}}</span>
        <span><label style="display:inline; margin-right:4px;">Type</label>{{category}}</span>
      </div>
    </div>
  </div>
$n$)
WHERE name = 'feedback_triage_form' AND html LIKE '%<label>Title</label>%';
