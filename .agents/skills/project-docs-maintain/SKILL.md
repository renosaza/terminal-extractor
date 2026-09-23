---
name: project-docs-maintain
description: Maintain a project's existing lean docs system after implementation, a durable decision, a changed compromise, or a work handoff. Update affected knowledge only; do not initialize or reorganize unrelated documentation automatically.
---
# Maintain project documentation

## Execution role

Honor the active session role and higher-priority instructions. In an explicitly identified Astra/Sol orchestrator session, delegate searches to Luna (choose effort for the task) and file changes/checks to a Terra worker; integrate evidence without editing files yourself. Workers execute their assigned scope directly without recursive delegation. Terra and lower-tier main sessions execute directly. Do not infer the running model from a config default, invent model IDs, or silently switch roles when delegation is unavailable; report the limitation and request an explicit direct-work override. Keep delegated briefs bounded and require sources, changed paths and actual check results.

Update only information needed by the next reader. Start with applicable AGENTS.md, active docs/constraints.md rules and affected files; read [references/layout.md](references/layout.md) only when the layout, record schema or language rule is needed.

- Follow the actual change into its callers/tests before stating changed behavior. Load architecture only for unfamiliar boundaries or invariants; read ADRs/debt only when relevant. Do not reread every index or whole graph.
- Keep root AGENTS.md pointing to docs/constraints.md and requiring its active rules before implementation. Update a prohibition only from an explicit authorized decision; preserve its source and change history. Do not turn a failed experiment or stale note into a permanent ban.
- Save durable new facts: a changed invariant, accepted decision and reason, accepted temporary compromise and exit conditions, verified failure mode that prevents repeated investigation, or necessary continuation state. If none changed, make no documentation edit.
- Preserve OKF `type` on concepts; update lifecycle `status` separately from task_status, decision_status and debt_status. Do not mark content verified merely because metadata checks pass.
- Update the existing record rather than create parallel summaries. Preserve accepted ADR history; use supersession for changed decisions. Distinguish current code from intended behavior and unresolved source conflicts. Follow local language rules and preserve machine schema identifiers.
- Split non-atomic work into independent outcomes. Several acceptance criteria for one fix do not require multiple cards, an epic or subagents. Use one owner per active task. Coordinate shared-file edits and check the combined result after integration when several agents contribute.
- Keep one authoritative tracker. Update local task state only if local cards own it; otherwise link canonical issues and avoid a second mutable status board.
- Before marking a task done, record Result: actual outcome, checks actually run, observed result and checked revision. Report blocked/not-run checks honestly; do not claim a proposed command passed. For paused or transferred work, replace Resume with done, next step, blocker, branch/revision and latest check. Remove stale handoff state when it ceases to help.
- Before resolving debt, verify the linked removal conditions with their explicit all/any rule. A cleanup task inherits every required gate. Update guides only for actual operational changes; never publish credentials or detailed transcripts.
- Refresh an existing graph only when indexed inputs changed and its tool supports this stack. Query bounded relevant results and expose incomplete coverage. Validate touched links, IDs and evidence using existing checks; report only material changes and verification limits.
