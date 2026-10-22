# prod -> dev whatsfresh mirror (task 609)

Prototype, proven on a laptop scratch DB (`wf_mirror_test`), not yet pointed at dev.

1. `mirror_sync.sql` - installs `mirror.*` functions into the target DB (catalog-driven: FK order, PKs, sequences).
2. `mirror-pull.sh <db>` - stages prod rows (read-only SSH COPY) into `mirror_stg.*`.
3. `select * from mirror.run()` - guards, upsert (parents first), delete-missing (children first), sequence reset. One transaction.
4. `mirror-verify.sh <db>` - per-table content hash, prod vs target.

Config is only in the SQL: excluded tables (`context_store`) and secret columns (`users`: password, appsmith_pwd, remember_token - never pulled; dev's values kept on update; placeholder `*` on insert).
Target needs `studio.fsma_classifications` (entity_types FK). Dev-only tables must not FK into mirrored tables (a blocked delete rolls the run back).

## Scheduling (n8n)
Workflow `mirror-nightly` (dev n8n, id gh8jnDAZq2C2kVuw; JSON in `n8n/workflows-dev-only/mirror-nightly.json`):
Nightly 04:00 (and a manual "Run now") -> `mirror.pull()` -> `mirror.run()`; any error goes to Slack #development.
Left INACTIVE until after cutover (cutover_status flipped, legacy etl-nightly/p01/p02 off before 11-01 03:00).
