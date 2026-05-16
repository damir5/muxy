---
status: accepted
tags: [agent-team, stage, code-structure]
created: 2026-05-16
created-by: agent-codex
reviewed-by: ""
parent: ""
relations:
  depends-on: [agent-team-stage-surface]
---

# Agent-Team Stage Window

The `agent-team` Stage surface in Muxy is split into three files with distinct responsibilities:

- `Muxy/Services/AgentTeamDaemonService.swift` discovers the daemon, caches `http_base_url`, polls `/api/status`, and converts the result into a `Snapshot`.
- `Muxy/Views/Stage/StageWindowController.swift` owns the floating `NSPanel`, embeds a `WKWebView`, resolves `stage-assets/index.html`, and translates the snapshot into the JavaScript payload consumed by the web UI.
- `Muxy/Views/Stage/StageBridge.swift` is the narrow bridge from web content back to native code and currently only supports a `refresh` action.

The panel is keyed to the active project or active worktree path. If `.agent-team` is missing for that path, the service clears cached daemon state and hides the panel. Asset lookup intentionally accepts two layouts: a flattened bundle root containing `index.html`, or a nested `stage-assets/index.html`. This exists to survive Xcode resource-bundling differences without changing Stage code.

Related: [[depends-on:agent-team-stage-surface]]
