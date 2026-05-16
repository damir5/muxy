---
status: accepted
tags: [agent-team, stage, tests]
created: 2026-05-16
created-by: agent-codex
reviewed-by: ""
parent: ""
relations:
  verifies: [agent-team-stage-surface]
  refines: [agent-team-stage-window]
---

# Agent-Team Daemon Discovery Backoff

`Tests/MuxyTests/Services/AgentTeamDaemonServiceTests.swift` locks down two non-obvious behaviors that future edits should preserve:

- Stage asset resolution must work when `index.html` is at the bundle root and when it is under `stage-assets/`. This protects the Stage panel from resource layout changes during Xcode bundling.
- Daemon discovery retries are rate-limited. `shouldAttemptDiscovery` must allow the first attempt immediately and suppress retries until `nextDiscoveryAttempt(after:)` has elapsed. This protects Muxy from repeatedly spawning or probing `agent-team` when the daemon is absent or broken.

If the transport changes from polling to SSE later, these tests are still relevant: asset resolution should remain tolerant, and daemon discovery should stay rate-limited even if steady-state updates become push-based.

Related: [[verifies:agent-team-stage-surface]] [[refines:agent-team-stage-window]]
