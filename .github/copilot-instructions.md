# Repo Guidance (Salesforce)

> The authoritative house standard is the `salesforce-developer` skill, vendored at
> `.claude/skills/salesforce-developer/`. Claude Code loads it automatically. Assistants
> that do not support skills should read its `references/` directly, then
> `.claude/references/local-standards.md` last — that file wins on conflict.
> The rules below are a summary, not the source of truth.

- Salesforce source lives under: `apex-common`, `apex-mocks`, `github-action-service`, `weather-app`.
- Follow SFDX layout inside each package directory (`main/default/**`, `test/classes/**`).
- For Apex: bulkify, avoid SOQL/DML in loops, and prefer `with sharing` unless explicitly required.
- For LWC: prefer `@wire`/LDS over imperative Apex, keep components small, and separate data from UI.
- Never hardcode org IDs, URLs, or secrets; use Named Credentials or config where needed.
- When creating Apex/LWC, start from templates in `docs/templates/` and replace all `{{Tokens}}`.
