# Repo Guidance (Salesforce)
- Salesforce source lives under: `apex-common`, `apex-mocks`, `github-action-service`, `weather-app`.
- Follow SFDX layout inside each package directory (`main/default/**`, `test/classes/**`).
- For Apex: bulkify, avoid SOQL/DML in loops, and prefer `with sharing` unless explicitly required.
- For LWC: prefer `@wire`/LDS over imperative Apex, keep components small, and separate data from UI.
- Never hardcode org IDs, URLs, or secrets; use Named Credentials or config where needed.
