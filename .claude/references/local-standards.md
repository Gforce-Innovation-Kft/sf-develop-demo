# Local Salesforce standards — sf-develop-demo

Read **last**, after the `salesforce-developer` skill's references. These **win** on conflict.

## API version

`sourceApiVersion` in `sfdx-project.json` is **65.0**. Generate all metadata at 65.0 — not 66.0,
not 67.0, and never a version carried over from another repo. The `salesforce-developer` skill's
own template repo is 67.0; that value does not apply here.

## Known defect — do not copy this shape

`weather-app/main/default/classes/WeatherReportsSelector.cls` never calls `setDataAccess()` or
passes a `DataAccess` value into its constructor — it relies on the bare no-arg
`fflib_SObjectSelector()` constructor. Verified against
`fflib-apex-common/sfdx-source/apex-common/main/classes/fflib_SObjectSelector.cls`: that leaves
`DataAccess` at its default (`LEGACY`) with `enforceFLS = false`, so **Field-Level Security is
never enforced** on this selector's queries — every field on every `SELECT` is returned
regardless of the running user's field permissions. Object-level CRUD is still checked
(`m_enforceCRUD` defaults to `true`), and sharing is still enforced (the class has no sharing
declaration of its own but extends the `with sharing` `fflib_SObjectSelector`, so it inherits
`with sharing`) — those two are not broken, only FLS is.

It is demo code that predates the standard. Do not use it as a pattern for new selectors, and do
not add `DataAccess.SYSTEM_MODE`/`USER_MODE` calls to _this_ class as a side effect of unrelated
work — fixing it is a separate, tracked ticket, not something to bundle in here.

## Salesforce MCP

This is the only GForce repo with a `.mcp.json` (Salesforce MCP). Prefer its tools over raw
`sf` CLI calls for org introspection.
