# CLAUDE.md - wf-server

Start every session by running:

```bash
bash /home/paul/Projects/wf-agents/agents/tools/plan/session-startup 58 claude
```

That is the whole startup routine. Arg 1 is the app id, arg 2 is your agent
role — pass `claude` so you get your own contract, not just the shared one.
In one pass it prints:

- **Your Contract** — shared operating contract plus your role contract
- **Available Scripts** — every runnable tool and workflow, with invocation and example
- **Connections** — database endpoints and which tool reaches each
- **Active Guidance** — architecture and workflow rules in force
- **Handoffs** — open notes left for whoever picks up next; mark them consumed once acted on
- **In Progress / Done Lately / Recent Impacts** — current work context

Do not go hunting for markdown first. Agent knowledge lives in the `guidance`
schema on localhost postgres (`contracts`, `agent_handoffs`, `guidance`,
`scripts`, `connections`, `startup_sections`), and the command above renders it.

Repo index: [wf-agents/README.md](/home/paul/Projects/wf-agents/README.md)
