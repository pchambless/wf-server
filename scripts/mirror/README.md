# prod -> dev whatsfresh mirror (task 609)

Prototype, proven on a laptop scratch DB (`wf_mirror_test`), not yet pointed at dev.

1. `mirror_sync.sql` - installs `mirror.*` functions into the target DB (catalog-driven: FK order, PKs, sequences).
2. `mirror-pull.sh <db>` - stages prod rows (read-only SSH COPY) into `mirror_stg.*`.
3. `select * from mirror.run()` - guards, upsert (parents first), delete-missing (children first), sequence reset. One transaction.
4. `mirror-verify.sh <db>` - per-table content hash, prod vs target.

Config is only in the SQL: excluded tables (`context_store`) and secret columns (`users`: password, appsmith_pwd, remember_token - never pulled; dev's values kept on update; placeholder `*` on insert).
Target needs `studio.fsma_classifications` (entity_types FK). Dev-only tables must not FK into mirrored tables (a blocked delete rolls the run back).

## Scheduling (n8n)
Workflow `wf-prod-to-dev-data` (dev n8n, id gh8jnDAZq2C2kVuw; JSON in `n8n/workflows-dev-only/wf-prod-to-dev-data.json`):
a `Schedule` trigger (04:00 daily by default; change the schedule if it should run more or less often) and a manual `Run now`
-> `mirror.pull()` -> `mirror.run()`; any error goes to Slack #development. The name says what it does, not how often.
Cutover is done and the legacy ETL workflows are unpublished, so this is the only thing that writes whatsfresh data into dev.
First manual run 2026-10-25 17:08 CT succeeded; afterwards prod and dev matched on all 15 tables (count + content hash).
