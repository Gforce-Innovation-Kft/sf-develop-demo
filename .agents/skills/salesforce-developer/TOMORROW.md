# Deferred verification — run these when the org / a fresh session is available

Built 2026-08-07. Everything that could be done without an org or a session restart is done and
checked. What remains needs something that was not available at build time.

Delete this file once all five are green.

---

## 1. Compile the `assets/` templates against a scratch org — REQUIRED

**Why it matters:** a template that does not compile teaches the wrong shape to every future
agent that reads it. These five classes have never been compiled — they were written against the
fflib API in `libs/fflib-apex-common` and the patterns in `sf-develop-demo`, but not deployed.

```bash
cd ~/gforce/sfdx_template_enterprise

# 1. Stage the templates into a real package directory with meta files
mkdir -p /tmp/asset-check/classes
for f in .claude/skills/salesforce-developer/assets/*.cls; do
  cp "$f" /tmp/asset-check/classes/
  printf '<?xml version="1.0" encoding="UTF-8"?>\n<ApexClass xmlns="http://soap.sforce.com/2006/04/metadata">\n    <apiVersion>67.0</apiVersion>\n    <status>Active</status>\n</ApexClass>\n' \
    > "/tmp/asset-check/classes/$(basename "$f")-meta.xml"
done

# 2. Scratch org with fflib already present
sf org create scratch -f config/scratch-orgs/ci.json -a asset-check -d 1
sf project deploy start --target-org asset-check --wait 30   # deploys the repo incl. libs/

# 3. Then the templates
sf project deploy start --source-dir /tmp/asset-check --target-org asset-check --wait 30

# 4. Run the template test class
sf apex run test --target-org asset-check --tests AccountsServiceTest \
  --result-format human --wait 20

sf org delete scratch --target-org asset-check --no-prompt
```

**Expect to fix at least one thing.** The parts most likely to be wrong:

- `super(false, true, true, true, DataAccess.USER_MODE)` — the 5-arg selector constructor is
  `private` in `fflib_SObjectSelector.cls:149`. If it is not reachable from a subclass, use the
  `DataAccess` overload that is public, or set enforcement another way. **Check this first.**
- `fflib_SObjectMocks.SObjectUnitOfWork` and `fflib_IDGenerator` — confirm both exist in the
  vendored fflib version, not just in upstream.
- `fflib_Match.sObjectWith(...)` argument-matcher signature.
- `acc.AnnualRevenue.addError(...)` — `addError` on a field value may need
  `acc.addError(Account.AnnualRevenue, '...')` form instead.

Fix the templates, not the standard. If the 5-arg constructor genuinely is not public, update
`references/apex-coding-rules.md` and `references/apex-patterns.md` to match whatever the correct
opt-in is — those two files now assert this constructor.

## 2. Prove the skill loads outside its home repo

Needs a **fresh Claude Code session** (skills are discovered at startup).

```bash
cd ~/gforce/sf-develop-demo    # NOT the template repo
claude
```

Ask: _"add a selector for Contact following our standards"_.

- ✅ `salesforce-developer` fires, and the generated selector has a `DataAccess.USER_MODE`
  constructor and API version **65.0** (that repo's `sourceApiVersion`), not 67.0.
- ❌ if it does not fire, the symlink is not being followed — check
  `ls -la ~/.claude/skills/salesforce-developer`.

## 3. Prove it does NOT over-fire

Same fresh session, in `~/gforce/sf-devops-agent`, ask for a change to `src/investigate.ts`.
`salesforce-developer` must **not** activate. That is what the `DO NOT TRIGGER` clause buys, and
it is the half that is easy to forget to test.

## 4. Re-apply the narrowed Managed Agents skill — costs a few cents

The skill directory was renamed `salesforce-standards` → `salesforce-deploy-failures` and the
coding-standards reference was removed.

```bash
cd ~/gforce/sf-devops-agent
npm run apply     # uploads the renamed skill, bumps the agent version
```

The old `salesforce-standards` skill stays in the workspace but is no longer attached — the agent
now references only what `apply` uploaded. Delete it in the Console if you want it tidy.

## 5. Regression — the investigator still works

```bash
npm run investigate -- fixtures/missing-dependency   # must still pass its assertions
```

The agent's system prompt changed (it no longer claims to carry coding standards) and its skill
changed. If confidence drops below 0.8 or the type changes, the prompt edit went too far.

Worth also re-running the two negative controls if the first result looks at all different:

```bash
npm run investigate -- fixtures/apex-compile-error
npm run investigate -- fixtures/apex-test-failure
```

---

## Not blocked on anything — already verified

- `npm run type-check`, `npm test` (20 offline checks) — green
- `agents/deployment-investigator.yaml` parses
- No contradictory `SECURITY_ENFORCED` guidance left outside the deliberate comparison table
- The skill is registered at personal scope (it appeared in the skills list without a repo prefix)
- Both symlinks resolve, including `references/` through the double hop

## Separately worth knowing

`sf-develop-demo/weather-app/main/default/classes/WeatherReportsSelector.cls` has **no
`DataAccess` constructor**, so it currently runs in system mode with no FLS, CRUD or sharing
enforcement. It is demo code, not in scope here, but it is a real instance of the defect the old
documentation caused — worth fixing when you are next in that repo.
