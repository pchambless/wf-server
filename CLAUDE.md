# CLAUDE.md - wf-server

Start every session in two steps.

1. Unless your first message already names an app or a task, run the menu
   prequel (about 1 KB) and ask the user which app to work on. It lists the apps
   with open-work counts and says how to choose:

```bash
bash /home/paul/Projects/wf-agents/agents/tools/plan/session-startup --menu claude whatsfresh
```

2. Run the full startup for the chosen app (58 if the user names none):

```bash
bash /home/paul/Projects/wf-agents/agents/tools/plan/session-startup <app id> claude whatsfresh
```

That is the whole startup routine. Arg 1 is the app id, arg 2 is your agent
role — pass `claude` so you get your own contract, not just the shared one —
and arg 3 is the project scope, which keeps local-desk and wf-marketing rules
out of a whatsfresh session. In one pass it prints:

- **Your Contract** — shared operating contract plus your role contract
- **Available Scripts** — every runnable tool and workflow, with invocation and example
- **Connections** — database endpoints and which tool reaches each
- **Active Guidance** — core rules in full plus an index of on-demand rules for your app; load a row when its trigger applies
- **Handoffs** — open notes left for whoever picks up next; mark them consumed once acted on
- **In Progress / Done Lately / Recent Impacts** — current work context

Do not go hunting for markdown first. Agent knowledge lives in the `guidance`
schema on localhost postgres (`contracts`, `agent_handoffs`, `guidance`,
`scripts`, `connections`, `startup_sections`), and the command above renders it.

Repo index: [wf-agents/README.md](/home/paul/Projects/wf-agents/README.md)
