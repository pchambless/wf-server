-- Task 659: the feedback grid is for picking a row, so it keeps only what picking needs:
-- #, Date, From, Page, Title, Status. Env, Type, Task and Trello are not lost: the triage form shows them
-- (Environment, Type, Task #, Trello) as soon as a row is selected. Env is hidden entirely (feedback is
-- essentially all from prod; dev rows are tests).

UPDATE support.html_templates
SET html = $g$<div class="table page-grid grid-fixed grid-scroll grid-sticky">
  <table>
    <colgroup>
      <col style="width:5%;">
      <col style="width:12%;">
      <col style="width:21%;">
      <col style="width:14%;">
      <col style="width:36%;">
      <col style="width:12%;">
    </colgroup>
    <thead>
      <tr>
        <th>#</th>
        <th>Date</th>
        <th>From</th>
        <th>Page</th>
        <th>Title</th>
        <th>Status</th>
      </tr>
    </thead>
    <tbody>
      {{#each data}}
      <tr class="grid-row" data-row-id="{{id}}">
        <td>{{id}}</td>
        <td>{{submitted}}</td>
        <td>{{from_user}} <span style="color:#6b7280;">({{account_name}})</span></td>
        <td>{{page_name}}</td>
        <td>{{title}}</td>
        <td style="color: {{status_color}}">{{status}}</td>
      </tr>
      {{/each}}
    </tbody>
  </table>
</div>
$g$
WHERE name = 'feedback_grid' AND html LIKE '%<th>Env</th>%';
