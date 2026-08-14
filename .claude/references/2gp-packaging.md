# 2GP packaging in this repo

Detail behind `CLAUDE.md`. The Dev Hub daily version limit and the dependency install order are
the two things that most often go wrong — read both before packaging.

## 2GP Packaging

Three **unlocked packages** are built from Dev Hub `gabor_dev`, chained by declared
dependencies in `sfdx-project.json`:

| Package             | Package Id (`0Ho`)   | Latest version (`04t`)          | Depends on     |
| ------------------- | -------------------- | ------------------------------- | -------------- |
| `fflib-apex-mocks`  | `0HogL000000421dSAA` | `04tgL000000M0arQAC` (0.1.0-1)  | —              |
| `fflib-apex-common` | `0HogL000000423FSAQ` | `04tgL000000M0cTQAS` (0.1.0-1)  | mocks          |
| `weather-app`       | `0HogL000000426TSAQ` | `04tgL000000M3X7QAK` (0.1.0-2)  | mocks + common |

`weather-app@0.1.0-1` (`04tgL000000M26PQAS`) is still aliased and installable; 0.1.0-2 is the
one the release flow last built.

```bash
# build a new version (validated — draws on the 6/day Dev Hub limit)
sf package version create --package weather-app --installation-key-bypass \
  --wait 45 --target-dev-hub gabor_dev

# install — dependencies first, in this order
sf package install --package 04tgL000000M0arQAC --target-org <alias> --wait 20 --no-prompt
sf package install --package 04tgL000000M0cTQAS --target-org <alias> --wait 20 --no-prompt
sf package install --package weather-app@0.1.0-2 --target-org <alias> --wait 20 --no-prompt
```

**2GP dependencies are not transitive.** Salesforce installs exactly what a package declares —
it does not walk the graph. `weather-app` therefore lists _both_ fflib packages in install
order; declaring only `fflib-apex-common` fails the build with "Install package
'fflib-apex-mocks' ... before you install 'fflib-apex-common'".

fflib is packaged from our own Dev Hub because upstream `apex-enterprise-patterns` publishes no
`04t` version IDs (no releases, no `packageAliases`) — there is nothing official to depend on.

**`sf package create` rewrites `sfdx-project.json` and silently drops the `dependencies` block**
of the entry it touches. Re-add it after creating or recreating any package.

Org-dependent unlocked packages are **not** usable here: Salesforce rejects them with
"Org-dependent unlocked packages can't have dependencies on other packages."

To discover a version's flattened dependency chain (install order) without parsing the project
file:

```bash
sf data query --use-tooling-api --target-org gabor_dev \
  --query "SELECT Dependencies FROM SubscriberPackageVersion WHERE Id = '04tgL000000M26PQAS'"
```
