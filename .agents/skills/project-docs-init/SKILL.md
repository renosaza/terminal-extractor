---
name: project-docs-init
description: Initialize the lean AGENTS.md and docs system for a new project or a project without organized documentation when setup is requested. Derive content from real code and requirements; use migration instead when existing knowledge must be reorganized.
---
# Initialize project documentation

## Execution role

Honor the active session role and higher-priority instructions. In an explicitly identified Astra/Sol orchestrator session, delegate searches to Luna (choose effort for the task) and file changes/checks to a Terra worker; integrate evidence without editing files yourself. Workers execute their assigned scope directly without recursive delegation. Terra and lower-tier main sessions execute directly. Do not infer the running model from a config default, invent model IDs, or silently switch roles when delegation is unavailable; report the limitation and request an explicit direct-work override. Keep delegated briefs bounded and require sources, changed paths and actual check results.

Read [references/layout.md](references/layout.md) for the target contract. Create the smallest useful project-specific documentation.

1. Inspect existing instructions, files, runtime/dependency manifests, tests and supplied requirements. Determine the canonical remote/tracker and artifact language from evidence and user instructions. Existing documentation takes precedence over blank templates; preserve it and switch to migration if reorganization is required.
2. Merge a short root AGENTS.md with existing instructions. Require reading active `docs/constraints.md` rules before implementation. Include project invariants, verified development/check commands, the canonical remote when known, and selective documentation pointers. Do not copy global policy into every project or invent commands, access, production readiness or repository state.
3. Create docs/constraints.md with source-backed project prohibitions and their exact scope; explicitly state when no additional prohibitions are known. Create docs/index.md as the concise OKF bundle index; keep any docs/README.md as a typed overview concept. Give every concept a YAML `type` and preserve the OKF/workflow metadata distinction in the contract. Create architecture and human guides only when actual code or requirements support meaningful content. Distinguish proposed design from implemented behavior. In an empty repository, document known purpose/constraints and unknowns; do not invent components or deployment steps.
4. Use the contract's paths as destinations when content exists; do not fill empty record folders with fictional ADRs, debt, tasks or epics. Create templates only when this project's workflow needs them. Do not create domains/ by default. A non-atomic current assignment can have independent tasks, but initialization alone does not justify a backlog.
5. Establish one authoritative tracker. For a project using external issues, link it rather than creating a duplicate local board. Introduce a code graph only when useful, using a proven stack-compatible existing tool; a short graph/README.md with targeted search guidance is sufficient when indexing is unavailable or unnecessary. State coverage honestly.
6. Check created links and metadata and run only commands that genuinely exist. Report created files, remaining unknowns and checks actually performed. Keep initialization separate from unrelated refactoring, dependency installation, remote changes or publication.
