# Enable Powerlevel10k instant prompt. Should stay close to the top of ~/.zshrc.
if [[ -r "${XDG_CACHE_HOME:-$HOME/.cache}/p10k-instant-prompt-${(%):-%n}.zsh" ]]; then
  source "${XDG_CACHE_HOME:-$HOME/.cache}/p10k-instant-prompt-${(%):-%n}.zsh"
fi

# Path to your oh-my-zsh installation.
export ZSH="$HOME/.oh-my-zsh"

# Set name of the theme to load
ZSH_THEME="powerlevel10k/powerlevel10k"

# Plugins
plugins=(
  git
  docker
  docker-compose
  node
  npm
  vscode
  zsh-autosuggestions
  zsh-syntax-highlighting
  zsh-completions
  command-not-found
  colored-man-pages
  extract
  copyfile
  copypath
)

source $ZSH/oh-my-zsh.sh

# User configuration

# Preferred editor
export EDITOR='vim'

# Salesforce CLI aliases
alias sfdx='sf'
alias sflogin='sf org login web'
alias sflogout='sf org logout'
alias sflist='sf org list'
alias sfdeploy='sf project deploy start'
alias sfpull='sf project retrieve start'
alias sftest='sf apex run test'
alias sforg='sf org display'

# Git aliases
alias gs='git status'
alias ga='git add'
alias gc='git commit'
alias gp='git push'
alias gl='git pull'
alias gco='git checkout'
alias gb='git branch'
alias gd='git diff'

# Docker aliases
alias dc='docker-compose'
alias dcup='docker-compose up'
alias dcdown='docker-compose down'
alias dclogs='docker-compose logs'

# General aliases
alias ll='ls -alF'
alias la='ls -A'
alias l='ls -CF'
alias ..='cd ..'
alias ...='cd ../..'

# Custom functions
function mkcd() {
  mkdir -p "$1" && cd "$1"
}

# Salesforce scratch org helper
function sfscratch() {
  if [ -z "$1" ]; then
    echo "Usage: sfscratch <alias>"
    return 1
  fi
  sf org create scratch --definition-file config/project-scratch-def.json --alias "$1" --set-default --duration-days 7
}

# Display welcome message
echo ""
echo "🚀 Salesforce Development Environment"
echo "======================================"
echo "Node version: $(node --version)"
echo "Java version: $(java -version 2>&1 | head -n 1)"
echo "SF CLI: $(sf version --json | jq -r '.version')"
echo ""
echo "Available commands:"
echo "  sf org list       - List all authenticated orgs"
echo "  sfscratch <name>  - Create a scratch org"
echo "  sfdeploy          - Deploy to default org"
echo ""

# To customize prompt, run `p10k configure` or edit ~/.p10k.zsh.
[[ ! -f ~/.p10k.zsh ]] || source ~/.p10k.zsh
