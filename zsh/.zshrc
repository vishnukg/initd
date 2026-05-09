if [[ -x /opt/homebrew/bin/brew ]]; then
  eval "$(/opt/homebrew/bin/brew shellenv)"
fi

local_bin="${HOME}/.local/bin"
if [[ -d "${local_bin}" && ":${PATH}:" != *":${local_bin}:"* ]]; then
  export PATH="${local_bin}:${PATH}"
fi

dotnet_tools="${HOME}/.dotnet/tools"
if [[ -d "${dotnet_tools}" && ":${PATH}:" != *":${dotnet_tools}:"* ]]; then
  export PATH="${dotnet_tools}:${PATH}"
fi

export ZSH="${HOME}/.oh-my-zsh"
ZSH_THEME=""
plugins=(git)

if [[ -f "${ZSH}/oh-my-zsh.sh" ]]; then
  source "${ZSH}/oh-my-zsh.sh"
fi

alias vi="nvim"
alias vim="nvim"

if command -v zoxide >/dev/null 2>&1; then
  eval "$(zoxide init zsh)"
fi

if command -v mise >/dev/null 2>&1; then
  eval "$(mise activate zsh)"
fi

if command -v starship >/dev/null 2>&1; then
  eval "$(starship init zsh)"
fi

# Auto-attach to tmux when opening a new terminal (skip if already inside tmux)
if command -v tmux >/dev/null 2>&1 && [[ -z "$TMUX" ]]; then
  exec tmux new-session -A -s main
fi
