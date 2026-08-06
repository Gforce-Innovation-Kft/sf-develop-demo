# Salesforce Development Container

A ready-to-use Salesforce development environment, built from the published
[`gforceinnovation/sf-devcontainer`](https://hub.docker.com/r/gforceinnovation/sf-devcontainer)
image. There is no local Dockerfile — `devcontainer.json` pulls
`gforceinnovation/sf-devcontainer:latest` directly, so opening the container never
triggers a local build.

## 🚀 What's Included

### Core Tools

- **Ubuntu 24.04** - Base operating system
- **Node.js 24.x** - JavaScript runtime
- **Java 17 (OpenJDK)** - Required for Salesforce CLI
- **Salesforce CLI v2** - with the `code-analyzer`, `sfdx-git-delta`, and
  `sfdx-browserforce-plugin` plugins pre-installed
- **Git**, **GitHub CLI (`gh`)** - version control and GitHub integration

### Development Utilities

- **jq**, **xmlstarlet** - JSON/XML processing
- **vim**, **nano** - text editors
- **htop**, **tree**, **less**, **build-essential**, **openssl**
- **ripgrep**, **fd**, **bat**, **eza**, **fzf**, **zoxide** - modern CLI replacements
- **git-delta** - configured as the system git pager (`core.pager`)
- **lazygit**

### Shell Environment

> **Version note:** the Starship-based shell described below ships in
> `gforceinnovation/sf-devcontainer` **v3.0.0, which has not been released
> yet**. `devcontainer.json` pulls `:latest`, which today resolves to
> **v2.0.0** and still has Oh My Zsh + Powerlevel10k. Treat this section as
> the target state, not necessarily what you'll see until v3.0.0 ships and
> `:latest` moves.

- **Zsh** - default shell, with a **Starship** prompt (no Oh My Zsh, no
  Powerlevel10k)
- **Plugins**, sourced directly (not via a framework): `zsh-autosuggestions`,
  `zsh-syntax-highlighting`
- One cached `compinit` for completions
- Command history persisted across rebuilds via a Docker volume mounted at
  `/commandhistory`

## 📦 Getting Started

### Prerequisites

- Visual Studio Code
- Docker Desktop
- VS Code Dev Containers extension

### Launch the Dev Container

1. **Open the project in VS Code**

   ```bash
   code .
   ```

2. **Reopen in Container**
   - Press `F1` or `Cmd+Shift+P` (Mac) / `Ctrl+Shift+P` (Windows/Linux)
   - Type: `Dev Containers: Reopen in Container`
   - First launch pulls the image if it isn't cached locally

3. **Start developing**
   `postCreateCommand` automatically runs `npm install` and
   `.devcontainer/post-create.sh`, which resolves and verifies your target org
   (see below).

## 🔐 Salesforce Authentication

**Auth is created and kept inside the container, isolated from your host.**
`~/.sf` and `~/.sfdx` are **named Docker volumes** (`devcontainer.json` →
`mounts`), not a bind mount of your host directories — so it persists across
rebuilds, but a login on your host machine is **not** visible in the
container and vice versa.

> **Why not just bind-mount the host's `~/.sf`?** That was the previous setup,
> and it's broken: `sf`'s stored auth tokens are encrypted with a key from the
> host OS's keychain (e.g. macOS Keychain). A Linux container can't read that
> keychain, so every org fails `sf org list` with `AuthDecryptError` — the
> credentials are *present* but undecryptable. Named volumes sidestep this
> entirely: the container creates and reads its own auth with its own key,
> and it never has to cross the host/container boundary.

- Log in from **inside the container**:

  ```bash
  sf org login web --alias myorg --set-default
  ```

  or non-interactively via an auth URL obtained on any machine already logged
  in (`sf org display --target-org <alias> --verbose --json | jq -r .result.sfdxAuthUrl`):

  ```bash
  echo "$SF_AUTH_URL" | sf org login sfdx-url --sfdx-url-stdin --alias myorg --set-default
  ```

- It survives `Rebuild Container` (the volume isn't touched by a rebuild) but
  **not** `Rebuild Container Without Cache` combined with removing the
  volumes, or `docker volume rm sf-develop-demo-sf-config sf-develop-demo-sfdx-config`.

**This means the container does NOT have access to orgs you've only
authorized on the host** — including if you were relying on that before this
change. Log in once inside the container per org you need here; production
access is now scoped to whichever container you explicitly authorize.

### `post-create.sh`

Runs automatically at container creation (via `postCreateCommand`). It:

1. Reads the current `target-org` from `sf config get target-org`. Since
   `.sf/` is gitignored and a fresh volume starts empty, it falls back to the
   `SF_DEFAULT_ORG_ALIAS` value set in `devcontainer.json`
   (`containerEnv`) if no target-org is configured yet.
2. Verifies the resolved org is actually authorized (`sf org display`). If
   it isn't — expected on a brand-new volume — the script exits non-zero and
   prints the exact `sf org login web --alias <org> --set-default` command
   to run, **inside the container**.

If you see that failure, log in inside the container and re-run
`.devcontainer/post-create.sh`, or reopen the container.

## 🛠️ Useful Commands

### Salesforce CLI Aliases (defined in the image's `.zshrc`)

```bash
sfl             # sf org list
sfo             # sf org open
sfd             # sf project deploy start
sfdp            # sf project deploy preview
sfr             # sf project retrieve start
sft             # sf apex run test --code-coverage --result-format human --wait 10
sfdelta [ref]   # sf sgd source delta --from <ref, default origin/main> --to HEAD
sfhelp          # print this list of shortcuts
devhelp         # show the full CLI tools cheatsheet (rendered with bat)
```

### File Listing Aliases

```bash
ls              # eza
ll              # eza -alF --git --group-directories-first
la              # eza -a
l               # eza -F
lt              # eza --tree --level=2
```

## 🎨 Customizing the Environment

There's no Dockerfile to edit or rebuild. Two supported ways to customize:

- **`~/.zshrc.local`** - sourced last by the image's `.zshrc`. Add your own
  aliases, functions, or environment tweaks here without touching the image.
- **VS Code's `dotfiles.repository` setting** - for a full personal dotfiles
  setup applied automatically on container creation.

`p10k configure` is not available once on sf-devcontainer ≥ 3.0.0 (Starship
replaces Powerlevel10k — see the version note under Shell Environment above).
On the current `:latest` (v2.0.0), Powerlevel10k is still present.

## 🔍 Troubleshooting

### Container won't start

- Ensure Docker Desktop is running
- Check Docker has enough resources (4GB+ RAM recommended)
- Try: `F1 > Dev Containers: Rebuild Container Without Cache`

### `post-create.sh` fails with "org is NOT authorized"

- Expected the first time you use a new alias, or on a fresh
  `sf-develop-demo-sf-config`/`sf-develop-demo-sfdx-config` volume (e.g. after
  `docker volume rm` or a first-ever container start). Follow the
  `sf org login web ...` command the script prints — run it **inside the
  container**, not on the host — then re-run `.devcontainer/post-create.sh`.
- Getting `AuthDecryptError` instead of "NOT authorized"? That means a login
  from a *different* environment (old host bind mount, a different machine)
  ended up in this volume. Re-run `sf org login web --alias <org> --set-default`
  inside this container to overwrite it with a decryptable one.

## 📚 Additional Resources

- [Salesforce CLI Command Reference](https://developer.salesforce.com/docs/atlas.en-us.sfdx_cli_reference.meta/sfdx_cli_reference/)
- [VS Code Dev Containers](https://code.visualstudio.com/docs/devcontainers/containers)
- [Starship prompt](https://starship.rs/)

## 🎯 Quick Start Example

```bash
# Inside the dev container

# 1. List authenticated orgs (authorized inside this container)
sfl

# 2. Deploy the weather-app package
sf project deploy start --source-dir weather-app

# 3. Run tests
sf apex run test --test-level RunLocalTests

# 4. Open the org
sfo
```

Enjoy your development environment! 🎉
