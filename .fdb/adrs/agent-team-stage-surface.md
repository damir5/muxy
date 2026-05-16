---
status: accepted
tags: [agent-team, stage, ui]
created: 2026-05-16
created-by: agent-codex
reviewed-by: ""
parent: ""
relations:
  refines: [agent-team-stage-window]
  verifies: [agent-team-daemon-discovery-backoff]
---

# Agent-Team Stage Surface

**Decision:** Muxy exposes `agent-team` activity through a floating Stage panel backed by a local daemon service instead of embedding terminal control directly in the app.

**Context:** The app needs a lightweight read-only surface for runs and reservations across the active project or worktree. The code in `Muxy/MuxyApp.swift`, `Muxy/Services/AgentTeamDaemonService.swift`, and `Muxy/Views/Stage/` shows that Muxy only needs discovery, polling, refresh, and rendering. It does not need to own tmux sessions or the `agent-team` control plane.

**Alternatives considered:**
- Query `agent-team` CLI on every refresh. Rejected because discovery is already separated from steady-state reads and the service caches the daemon base URL.
- Talk to terminal sessions or tmux directly from Muxy. Rejected because that would duplicate `agent-team` orchestration rules inside the GUI app.
- Hide the Stage when the daemon is unavailable forever. Rejected because the service retries discovery after a backoff and exposes manual refresh.

**Consequences:** Muxy stays a thin display client. The service discovers the daemon with `agent-team daemon status --root <project>`, caches `http_base_url`, then reads `/api/status` for updates. The current implementation uses a 3-second timer plus a 30-second discovery backoff, so future work on SSE or richer stage detail should stay inside the daemon/service boundary rather than leaking transport logic into the window controller.

Related: [[refines:agent-team-stage-window]] [[verifies:agent-team-daemon-discovery-backoff]]
