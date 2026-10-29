# n8n Prod Upgrade Runbook — 2.43.5 → 3.0.1

Status as of 2026-10-28. This runbook captures the exact, verified procedure for
upgrading **prod** (`v2-n8n.whatsfresh.app`, `root@142.93.113.124`) to n8n 3.0.1,
which is the remediation for the 2026-10-28 security advisory batch (see
"Why 3.0.1" below). Dev (`n8n.whatsfresh.app`, `142.93.204.168`) is already on
3.0.1 and soaking.

## Why 3.0.1 (not 2.46.1)

The 12 advisories in the 2026-10-28 batch are **patched only in `>= 3.0.1`** per
GitHub's advisory data (every one carries `patched = ">= 3.0.1"`). 2.46.1 does
NOT clear them. Of the 12, the two that squarely apply to our usage are both High:

- **GHSA-9p7v-45m2-wxgj** — Code node execution in the n8n main process.
  We run 13 Code nodes on prod, 30 on dev. Directly applicable.
- **GHSA-gx3v-3x3v-f8r5** — Insufficient isolation in workflow expression
  evaluation. Applies to essentially all workflows.

The third High (GraphicsMagick) and 7 of 9 Mediums target nodes we do not use
(MongoDB, Asana, OracleDB vector store, NocoDB, Browser Use, Chat Trigger).
Three Mediums are "maybe" (OAuth connect flow, MCP OAuth redirect, credential
header forwarding) — lower stakes, not blocking.

## Preconditions (all already satisfied as of 2026-10-28, re-verify before running)

1. **Dev has soaked on 3.0.1** for 2-3 days with no issues — especially Code-node
   and expression-heavy workflows (3.x defaults the expression engine to `vm`,
   a behavioral change from `legacy`).
2. **No one is using prod.** The upgrade causes ~15-30s downtime. Confirm the
   colleague who uses prod is off `v2-n8n.whatsfresh.app`.
3. **Prod compose parity is green.** Already reconciled 2026-10-28:
   - `N8N_VERSION` pin bumped to the running version.
   - `DB_POSTGRESDB_POOL_SIZE=10` added to `/home/n8n/n8n.env` (prod runs a
     10-connection pool; dev does not set it. Must be preserved — see
     `scripts/production/provision.sh:208`).
   - Re-verify: `ssh root@142.93.113.124 'bash /tmp/parity.sh'` after copying
     `scripts/n8n/check-compose-parity.sh` to `/tmp/parity.sh`. Must print
     `PARITY: compose reproduces the running container`.

## Procedure

All commands run from the laptop in `/home/paul/Projects/wf-server`.

### 1. Preflight (read-only, changes nothing; pulls the 3.0.1 image)

```bash
bash scripts/n8n/n8n-upgrade.sh prod --to 3.0.1 --allow-major
```

`--allow-major` is REQUIRED (2 → 3 is a major jump; the preflight blocks it
otherwise). Expect `RESULT: PREFLIGHT OK`. If the parity check FAILS, stop and
reconcile (see Preconditions 3) before proceeding.

### 2. Apply (causes downtime; has backup + verify + auto-rollback)

```bash
bash scripts/n8n/n8n-upgrade.sh prod --to 3.0.1 --apply --allow-major
```

What it does, in order (all automatic):
1. Re-run preflight.
2. Backup: `pg_dump` of n8n's public schema + tar the data dir (holds the
   encryption key), then **restore the dump into a scratch DB to prove it
   restores** before stopping anything.
3. Stop + remove the 2.43.5 container (downtime starts; its image stays on disk).
4. `compose up` on 3.0.1.
5. Verify: wait for healthy (up to 4 min for migrations), confirm version is
   3.0.1, confirm workflow/active/credential/webhook counts are unchanged, scan
   the startup log for migration/encryption/activation/connection errors, hit
   the readiness endpoint.
6. **Auto-rollback to 2.43.5 if anything fails.**

Expect `RESULT: UPGRADED to 3.0.1 - verified`.

> NOTE: unlike dev, the wrapper runs **no external smoke test** for prod (the
> `server-query` webhook smoke test is dev-only in `n8n-upgrade.sh`). After the
> apply, manually confirm prod: hit a known webhook, open the editor, run a
> Code-node workflow.

### 3. Manual post-upgrade verification

- Editor loads at `https://v2-n8n.whatsfresh.app`.
- A Code-node workflow executes (the core applicable advisory is about Code
  nodes — confirm they still run on 3.x).
- An expression-heavy workflow produces correct output (new `vm` engine).
- The `server-query` webhook responds (our `pg_query`/deploy tooling depends on
  it): `cd /home/paul/Projects/wf-server && source scripts/deploy-lib/pg-query.sh && pg_query "select 1 as ok"`.

### 4. Soak, then finalize

Rollback stays available until finalize:

```bash
bash scripts/n8n/n8n-upgrade.sh prod --rollback     # undo (restores 2.43.5 + pre-upgrade data)
bash scripts/n8n/n8n-upgrade.sh prod --finalize      # accept; rollback refused afterward
```

## Rollback notes

- n8n DB migrations do NOT reverse. Rollback = restore the pre-upgrade dump +
  previous image. The tooling handles this; the backup lives in
  `/var/backups/n8n/` on prod.
- A rollback that succeeds leaves prod on 2.43.5 — **still exposed to the
  advisory batch.** A rollback is not a safe resting state for this upgrade; it
  is a "something broke, investigate and retry" state. Treat it as an incident.

## After prod is on 3.0.1

- Flip the version tracker to the 3.x line: in `deployment.version_feed`, set the
  n8n row's `expected.track_major` from `"2"` to `"3"` so `latest_on_major`
  tracks the line both droplets then run. (While dev=3.x and prod=2.x, the feed
  tracks only one major — see the version-tracking notes.)
- Run `infra-probe` (Run now) so the view shows prod=3.0.1.
- Consider Phase B (external task runners) — see `n8n-external-runners-plan.md`.
