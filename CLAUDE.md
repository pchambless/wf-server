# CLAUDE.md - wf-server

Start every session by running:

```bash
bash /home/paul/Projects/wf-agents/agents/tools/plan/session-startup
```

That is the whole startup routine. In one pass it prints:

- **Available Scripts** — every runnable tool and workflow, with invocation and example
- **Connections** — database endpoints and which tool reaches each
- **Active Guidance** — architecture and workflow rules in force
- **In Progress / Done Lately / Recent Impacts** — current work context

Do not go hunting for markdown first. Agent knowledge lives in the `guidance`
schema on localhost postgres (`guidance`, `scripts`, `connections`,
`startup_sections`), and the command above renders it.

Repo index and role contracts: [wf-agents/README.md](/home/paul/Projects/wf-agents/README.md)
