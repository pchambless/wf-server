# n8n External Task Runners — Phase B hardening plan

Status as of 2026-10-28. This is a **follow-up hardening project**, NOT a
prerequisite for the 3.0.1 security upgrade. Do it after local/dev/prod are on
3.0.1 and stable.

## Why

Task runners (the sandbox that executes Code nodes) have run in **internal**
mode by default since n8n 2.0 — the runner lives inside the main n8n process.
The 2026-10 advisory batch (and a steady stream of similar sandbox-escape CVEs
over recent months) shows a recurring class of bug: an authenticated user crafts
a Code-node or expression payload that escapes the sandbox.

Per n8n's own advisories (e.g. GHSA-jjpj-p2wh-qf23, GHSA-8398-gmmx-564h), the
blast radius differs sharply by mode:

- **Internal mode (current):** a successful escape can mean full compromise of
  the n8n host.
- **External mode:** untrusted code runs in a separate sidecar container; an
  escape is confined to the sidecar, not the main n8n process / host.

We are Code-node-heavy on prod (13 nodes), so external mode is the recommended
posture for defense-in-depth against the *next* escape (upgrading to 3.0.1 fixes
the *known* holes; external mode limits the *unknown future* ones).

## What it involves

External mode is a real infra change, not a flag flip:

1. A **second container** (the task-runner launcher / broker sidecar) alongside
   n8n, sharing a broker URI.
2. New env on the n8n container:
   - `N8N_RUNNERS_MODE=external`
   - `N8N_RUNNERS_AUTH_TOKEN=<shared secret>` (also given to the sidecar)
   - broker/launcher wiring per n8n's "set up task runners" docs.
3. Compose changes: add the runner service to `scripts/n8n/compose.yaml`
   (shared across dev/prod), put the auth token + any host-specific bits in
   `/home/n8n/n8n.env` (per-host, mode 600). Keep the compose-parity check
   (`check-compose-parity.sh`) green — it will need to learn about the new
   service/env.

## Known behavioral risks (why this needs its own rehearsal)

External mode changes the Code-node execution context. Community reports show it
has broken, for some users:

- `$evaluateExpression`, `$node['nodeName']` access from Code nodes.
- External module imports inside Code nodes (e.g. jsdom).
- Python Code nodes need the runner image to actually have Python (we already
  saw "Python 3 is missing" on the 3.0.1 internal runner — external mode makes
  the runtime the sidecar's responsibility).

So this must be rehearsed against a copy of real workflows (use
`rehearse-upgrade.sh`-style isolation), with every Code-node workflow exercised,
before it touches prod.

## Suggested sequence

1. Prototype external mode on the **local** laptop n8n (now on 3.0.1, disposable).
   Add the sidecar, flip the env, run the `local-query` webhook + any Code-node
   workflow. Confirm Code nodes still execute and return correct output.
2. Catalogue which prod/dev Code nodes use the at-risk patterns
   (`$node[...]`, external imports, Python) and test those specifically.
3. Roll to dev, soak, then prod — same canary discipline as the version upgrade.

## Not blocking

If this proves disruptive, 3.0.1 in internal mode is still the correct, patched
state for the current advisory batch. External mode is strictly additional
hardening and can wait until it's proven non-disruptive for our workflow set.
