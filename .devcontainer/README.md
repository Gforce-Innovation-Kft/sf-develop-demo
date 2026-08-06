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

**Auth is inherited from the host, not created in the container.** The host's
`~/.sf` and `~/.sfdx` directories are bind-mounted into the container
(`devcontainer.json` → `mounts`), so a login done on either side is visible on
both:

- Log in once on your host machine:

  ```bash
  sf org login web --alias myorg --set-default
  ```

  The container sees that authorization immediately — no need to log in again
  inside the container.

- A login run *inside* the container (`sf org login web ...`) writes to the
  same bind-mounted directory, so it persists back to the host too.

**This means the container has access to every org you have authorized on the
host, including production.** There is no isolation between host and
container credentials — treat the container with the same care you'd give
your host shell.

### `post-create.sh`

Runs automatically at container creation (via `postCreateCommand`). It:

1. Verifies `~/.sf` is actually mounted (fails with a clear message if not).
2. Reads the current `target-org` from `sf config get target-org`. Since
   `.sf/` is gitignored and never reaches a fresh clone, it falls back to the
   `SF_DEFAULT_ORG_ALIAS` value set in `devcontainer.json`
   (`containerEnv`) if no target-org is configured yet.
3. Verifies the resolved org is actually authorized (`sf org display`). If
   it isn't, the script exits non-zero and prints the exact
   `sf org login web --alias <org> --set-default` command to run.

If you see that failure, log in (on the host or in the container — either
works) and re-run `.devcontainer/post-create.sh`, or reopen the container.

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

`p10k configure` is not available — there is no Powerlevel10k in this image.

## 🔍 Troubleshooting

### Container won't start

- Ensure Docker Desktop is running
- Check Docker has enough resources (4GB+ RAM recommended)
- Try: `F1 > Dev Containers: Rebuild Container Without Cache`

### `post-create.sh` fails with "org is NOT authorized"

- This is expected the first time you use a new alias, or if your host
  session expired. Follow the `sf org login web ...` command the script
  prints, then re-run `.devcontainer/post-create.sh`.
- If it fails with "`~/.sf` is not mounted" instead, check the `mounts` entry
  in `.devcontainer/devcontainer.json` and rebuild the container.

## 📚 Additional Resources

- [Salesforce CLI Command Reference](https://developer.salesforce.com/docs/atlas.en-us.sfdx_cli_reference.meta/sfdx_cli_reference/)
- [VS Code Dev Containers](https://code.visualstudio.com/docs/devcontainers/containers)
- [Starship prompt](https://starship.rs/)

## 🎯 Quick Start Example

```bash
# Inside the dev container

# 1. List authenticated orgs (inherited from the host)
sfl

# 2. Deploy the weather-app package
sf project deploy start --source-dir weather-app

# 3. Run tests
sf apex run test --test-level RunLocalTests

# 4. Open the org
sfo
```

Enjoy your development environment! 🎉
