# Salesforce Development Container

A complete development environment for Salesforce development with all necessary tools pre-installed.

## 🚀 What's Included

### Core Tools

- **Ubuntu 22.04** - Base operating system
- **Node.js 18.x** - JavaScript runtime
- **Java 17 (OpenJDK)** - Required for Salesforce CLI
- **Salesforce CLI** - Latest version
- **Git** - Version control
- **GitHub CLI** - GitHub integration

### Development Utilities

- **jq** - JSON processor
- **xmlstarlet** - XML processor and validator
- **vim/nano** - Text editors
- **htop** - Process viewer
- **tree** - Directory structure viewer

### Shell Environment

- **Zsh** - Default shell
- **Oh My Zsh** - Zsh framework
- **Powerlevel10k** - Beautiful and fast prompt theme
- **Plugins**:
  - zsh-autosuggestions
  - zsh-syntax-highlighting
  - zsh-completions
  - git, docker, node, npm, vscode plugins

## 📦 Getting Started

### Prerequisites

- Visual Studio Code
- Docker Desktop
- VS Code Remote - Containers extension

### Launch the Dev Container

1. **Open the project in VS Code**

   ```bash
   code .
   ```

2. **Reopen in Container**
   - Press `F1` or `Cmd+Shift+P` (Mac) / `Ctrl+Shift+P` (Windows/Linux)
   - Type: `Remote-Containers: Reopen in Container`
   - Wait for the container to build (first time takes a few minutes)

3. **Start developing!**
   The container will automatically:
   - Install all dependencies
   - Mount your workspace at `/workspace`
   - Persist Salesforce CLI authentication

## 🔐 Salesforce Authentication

### JWT Authentication (for CI/CD)

```bash
sf org login jwt \
  --username your@email.com \
  --jwt-key-file certs/server.key \
  --client-id YOUR_CLIENT_ID \
  --alias devhub \
  --set-default-dev-hub \
  --instance-url https://login.salesforce.com
```

### Web Authentication (interactive)

```bash
sf org login web --alias myorg --set-default
```

## 🛠️ Useful Commands

### Salesforce CLI Aliases

```bash
sflist          # List all orgs
sforg           # Display org info
sfdeploy        # Deploy to org
sfpull          # Retrieve from org
sftest          # Run Apex tests
sfscratch <name> # Create scratch org
```

### Git Aliases

```bash
gs              # git status
ga              # git add
gc              # git commit
gp              # git push
gl              # git pull
gco             # git checkout
```

### Docker Aliases

```bash
dc              # docker-compose
dcup            # docker-compose up
dcdown          # docker-compose down
```

## 📁 Workspace Structure

Your local workspace is mounted at `/workspace` inside the container. All changes are synced in real-time.

Salesforce CLI configurations are persisted:

- `~/.sfdx` - Legacy SFDX config
- `~/.sf` - New SF CLI config

## 🎨 Customizing the Environment

### Modify Zsh Configuration

Edit `.devcontainer/.zshrc` to add your own aliases and functions.

### Modify Powerlevel10k Theme

Run inside the container:

```bash
p10k configure
```

### Add More Tools

Edit `.devcontainer/Dockerfile` and rebuild:

```bash
# Press F1 > Remote-Containers: Rebuild Container
```

## 🔍 Troubleshooting

### Container won't start

- Ensure Docker Desktop is running
- Check Docker has enough resources (4GB+ RAM recommended)
- Try: `F1 > Remote-Containers: Rebuild Container Without Cache`

### Salesforce CLI authentication issues

- Check your JWT key is in `certs/server.key`
- Verify Connected App settings in Salesforce
- Ensure callback URL uses HTTPS

### Zsh theme not loading

- The theme should load automatically
- If not, run: `source ~/.zshrc`

## 📚 Additional Resources

- [Salesforce CLI Command Reference](https://developer.salesforce.com/docs/atlas.en-us.sfdx_cli_reference.meta/sfdx_cli_reference/)
- [VS Code Remote Containers](https://code.visualstudio.com/docs/remote/containers)
- [Oh My Zsh Documentation](https://github.com/ohmyzsh/ohmyzsh)
- [Powerlevel10k Configuration](https://github.com/romkatv/powerlevel10k)

## 🎯 Quick Start Example

```bash
# Inside the dev container

# 1. List authenticated orgs
sf org list

# 2. Create a scratch org
sfscratch my-feature-org

# 3. Deploy your code
sf project deploy start --source-dir weather-app

# 4. Run tests
sf apex run test --test-level RunLocalTests

# 5. Open the org
sf org open
```

Enjoy your development environment! 🎉
