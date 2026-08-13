# Secret-bearing metadata templates

Custom Metadata records whose values include credentials. Rendered and deployed
by `sf-env-config-apply` **after** the artifact lands, so the credential never
enters the artifact.

## Why not just use `replacements`?

Because the artifact is uploaded and retained. Anything baked in at convert time
is retained with it, and the rollback window is however long artifact retention
is set to. A private key inside a stored artifact is a private key you now have
to rotate on a schedule you did not choose.

This repo used to do exactly that — `sfdx-project.json` injected
`GITHUB_PRIVATE_KEY_BASE64` at convert time. It does not any more.

## How a template works

- One file per record: `customMetadata/<Object>.<Record>.md-meta.xml.tpl`
- `${VAR}` placeholders are filled by `envsubst` from the job's environment
- Values come from **GitHub Environment secrets**, wired in the caller workflow
- An **unresolved placeholder fails the deployment**. Shipping a literal
  `${GITHUB_APP_KEY_B64}` into an org is worse than failing: the record looks
  populated and the integration breaks at runtime instead.
- Rendered files are shredded on every exit path, success or failure

## Required secrets

Set these per environment (`gh secret set NAME --env <environment>`):

| Secret               | Used by                                        | Notes                                          |
| -------------------- | ---------------------------------------------- | ---------------------------------------------- |
| `GITHUB_APP_KEY_B64` | `GitHub_App_Settings.salesforce_gforce_devhub` | base64 of the GitHub App's `.pem`, single line |

Non-secret values (`${SF_ENV_LABEL}`) come from
`config/environments/<env>.json`, so a template can mix both — only the
credentials need to be secrets.

To produce the base64 without a trailing newline:

```bash
base64 -i github-app.pem | tr -d '\n' | gh secret set GITHUB_APP_KEY_B64 --env integration
```

## The committed metadata still has a placeholder

`github-action-service/main/default/customMetadata/GitHub_App_Settings...` keeps
`GITHUB_PRIVATE_KEY_BASE64_PLACEHOLDER` as its committed value. That is
deliberate: the artifact deploys the record with an inert placeholder, and this
template immediately overwrites the field with the real value. The record is
therefore never _absent_ — only briefly non-functional, within a single
deployment.
