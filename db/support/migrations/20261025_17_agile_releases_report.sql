-- Task 681: Releases report on the agile board (button in group 11, next to Trello Report). For each planned release (Sprints
-- under agile.f_release_epic_id()): its state / target date / progress, then its tasks (with their topical sprint and epic,
-- FB markers, deployed date). Last group: how many open tasks are NOT planned, listing the High priority ones as candidates.
-- Reads only agile.vw_agile_cache, agile.vw_release_state, agile.f_feedback_ids. No colons in the SQL (params are :name).

INSERT INTO support.html_templates (name, platform, title, css, hydrate, html, created_by)
VALUES (
'rpt_agile_releases_hdr', 'report', 'Planned releases', '{rpt-hdr}',
$h1$with rel as (
  select r.id, rs.total_count, rs.done_count
    from agile.vw_agile_cache r
    join agile.vw_release_state rs on rs.id = r.id
)
select
  'Planned releases' as subject,
  to_char(now(), 'YYYY-MM-DD HH12') || chr(58) || to_char(now(), 'MI AM') as generated,
  (select count(*) from rel) as releases,
  coalesce((select sum(total_count) from rel), 0) as planned_tasks,
  coalesce((select sum(done_count) from rel), 0) as planned_done,
  (select count(*) from agile.vw_agile_cache t
    where t.page_type = 'Task' and t.status <> 'Done' and t.target_release_id is null) as unplanned_open$h1$,
$t1$<div class="report">
  <div class="header">
    <div class="header-bar">
      <div class="header-center">
        <h1>{{subject}}</h1>
      </div>
      <div class="header-right">
        <div class="generated">{{generated}}</div>
        <button type="button" class="print-btn">Print</button>
      </div>
    </div>
    <div class="header-meta">
      <div class="info-card"><div class="label">Releases</div><div class="value">{{releases}}</div></div>
      <div class="info-card"><div class="label">Planned tasks</div><div class="value">{{planned_tasks}}</div></div>
      <div class="info-card"><div class="label">Done</div><div class="value">{{planned_done}}</div></div>
      <div class="info-card"><div class="label">Not planned (open)</div><div class="value">{{unplanned_open}}</div></div>
    </div>
  </div>
</div>$t1$,
'claude'),
(
'rpt_agile_releases_body', 'report', 'Planned releases', '{table, rpt-grid}',
$h2$with rel as (
  select r.id, r.page_name, r.target_date, rs.state, rs.done_count, rs.total_count,
         row_number() over (order by r.target_date nulls last, r.id) as rn
    from agile.vw_agile_cache r
    join agile.vw_release_state rs on rs.id = r.id
), planned as (
  select rel.rn, t.id, t.page_name as title, t.status, t.priority, t.deployed_on,
         agile.f_feedback_ids(t.id, 'Task') as fb,
         coalesce(sp.page_name, '') || case when ep.page_name is not null then ' (' || ep.page_name || ')' else '' end as sprint_epic
    from rel
    join agile.vw_agile_cache t on t.target_release_id = rel.id and t.page_type = 'Task'
    left join agile.vw_agile_cache sp on sp.id = t.parent_id
    left join agile.vw_agile_cache ep on ep.id = sp.parent_id
), open_unplanned as (
  select count(*) as n from agile.vw_agile_cache t
   where t.page_type = 'Task' and t.status <> 'Done' and t.target_release_id is null
)
select rn::int as ord, 0 as seq, null::int as id, '' as task_no,
       upper(page_name) || '  -  ' || state || coalesce('  -  target ' || to_char(target_date, 'YYYY-MM-DD'), '')
         || '  -  ' || done_count || ' of ' || total_count || ' done' as title,
       '' as sprint_epic, '' as status, '' as priority, '' as fb, '' as deployed, 'group-hdr' as row_class
  from rel
union all
select rn::int, 1, id, id::text, title, sprint_epic, status, coalesce(priority, ''),
       coalesce('FB ' || fb, ''), coalesce(to_char(deployed_on, 'YYYY-MM-DD'), ''), ''
  from planned
union all
select 9000, 0, null::int, '', 'NOT PLANNED (Later) - ' || n || ' open tasks. The High priority ones are listed as candidates to promote.',
       '', '', '', '', '', 'group-hdr'
  from open_unplanned
union all
select 9000, 1, t.id, t.id::text, t.page_name,
       coalesce(sp.page_name, '') || case when ep.page_name is not null then ' (' || ep.page_name || ')' else '' end,
       t.status, coalesce(t.priority, ''), coalesce('FB ' || agile.f_feedback_ids(t.id, 'Task'), ''), '', ''
  from agile.vw_agile_cache t
  left join agile.vw_agile_cache sp on sp.id = t.parent_id
  left join agile.vw_agile_cache ep on ep.id = sp.parent_id
 where t.page_type = 'Task' and t.status <> 'Done' and t.target_release_id is null and t.priority = 'High'
order by ord, seq, id$h2$,
$t2$<table class="rpt-grid">
  <thead>
    <tr>
      <th style="width: 7%;">Task</th>
      <th style="width: 34%;">Title</th>
      <th style="width: 27%;">Sprint (Epic)</th>
      <th style="width: 9%;">Status</th>
      <th style="width: 8%;">Priority</th>
      <th style="width: 7%;">From</th>
      <th style="width: 8%;">Deployed</th>
    </tr>
  </thead>
  <tbody>
    {{#each data}}
    <tr class="{{row_class}}">
      <td>{{task_no}}</td>
      <td>{{title}}</td>
      <td>{{sprint_epic}}</td>
      <td>{{status}}</td>
      <td>{{priority}}</td>
      <td>{{fb}}</td>
      <td>{{deployed}}</td>
    </tr>
    {{/each}}
  </tbody>
</table>$t2$,
'claude');

INSERT INTO support.action_components (group_id, component_name, label, action_type, actions, visible_when, ordr, is_active)
VALUES (11, 'agile_releases_report', 'Releases', 'open_report',
        '{"templates": ["rpt_agile_releases_hdr", "rpt_agile_releases_body"]}'::jsonb, '"always"'::jsonb, 3, true);
