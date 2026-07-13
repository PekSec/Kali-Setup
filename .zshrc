# -------------------------------------------------------------------
# Powerlevel10k instant prompt
# Keep this block close to the top of ~/.zshrc.
# -------------------------------------------------------------------
if [[ -r "${XDG_CACHE_HOME:-$HOME/.cache}/p10k-instant-prompt-${(%):-%n}.zsh" ]]; then
    source "${XDG_CACHE_HOME:-$HOME/.cache}/p10k-instant-prompt-${(%):-%n}.zsh"
fi

# -------------------------------------------------------------------
# Oh My Zsh base
# -------------------------------------------------------------------
export ZSH="$HOME/.oh-my-zsh"
export ZSH_CUSTOM="${ZSH_CUSTOM:-$ZSH/custom}"

# -------------------------------------------------------------------
# Theme
# -------------------------------------------------------------------
ZSH_THEME="powerlevel10k/powerlevel10k"

# -------------------------------------------------------------------
# Oh My Zsh update behavior
# -------------------------------------------------------------------
zstyle ':omz:update' mode reminder
zstyle ':omz:update' frequency 13

# -------------------------------------------------------------------
# Completion behavior
# -------------------------------------------------------------------
CASE_SENSITIVE="false"
HYPHEN_INSENSITIVE="true"
DISABLE_AUTO_TITLE="true"
ENABLE_CORRECTION="false"

zstyle ':completion:*' menu select
zstyle ':completion:*' matcher-list 'm:{a-zA-Z}={A-Za-z}' 'm:{a-zA-Z-_}={A-Za-z_-}'
zstyle ':completion:*' use-cache on
zstyle ':completion:*' cache-path "${XDG_CACHE_HOME:-$HOME/.cache}/zsh/zcompcache"

if [[ -n "$LS_COLORS" ]]; then
    zstyle ':completion:*' list-colors "${(s.:.)LS_COLORS}"
fi

# -------------------------------------------------------------------
# History
# -------------------------------------------------------------------
HISTFILE="${ZDOTDIR:-$HOME}/.zsh_history"
HISTSIZE=50000
SAVEHIST=50000

setopt EXTENDED_HISTORY
setopt APPEND_HISTORY
setopt INC_APPEND_HISTORY
setopt SHARE_HISTORY
setopt HIST_EXPIRE_DUPS_FIRST
setopt HIST_IGNORE_DUPS
setopt HIST_IGNORE_ALL_DUPS
setopt HIST_FIND_NO_DUPS
setopt HIST_SAVE_NO_DUPS
setopt HIST_IGNORE_SPACE
setopt HIST_REDUCE_BLANKS
setopt HIST_VERIFY

# -------------------------------------------------------------------
# Shell behavior
# -------------------------------------------------------------------
setopt AUTO_CD
setopt AUTO_PUSHD
setopt PUSHD_IGNORE_DUPS
setopt PUSHD_SILENT
setopt INTERACTIVE_COMMENTS
setopt LONG_LIST_JOBS
setopt COMPLETE_IN_WORD

unsetopt BEEP
unsetopt CORRECT
unsetopt CORRECT_ALL

# -------------------------------------------------------------------
# PATH
# -------------------------------------------------------------------
typeset -U path PATH

export GOPATH="$HOME/go"

_path_prepend() {
    [[ -d "$1" ]] && path=("$1" "${path[@]}")
}

_path_append() {
    [[ -d "$1" ]] && path+=("$1")
}

# User-local binaries should usually have priority.
_path_prepend "$HOME/.local/bin"
_path_prepend "$HOME/bin"

# Standard system binary paths.
_path_append "/usr/local/sbin"
_path_append "/usr/local/bin"
_path_append "/usr/sbin"
_path_append "/usr/bin"
_path_append "/sbin"
_path_append "/bin"

# Common optional system locations.
_path_append "/opt/bin"
_path_append "/opt/local/bin"
_path_append "/snap/bin"

# Language/toolchain binaries.
_path_append "/usr/local/go/bin"
_path_append "$GOPATH/bin"
_path_append "$HOME/.cargo/bin"

export PATH

# -------------------------------------------------------------------
# Plugin loader
# Only loads plugins that actually exist.
# Prevents startup warnings from missing custom plugins.
# -------------------------------------------------------------------
plugins=()

_omz_plugin_exists() {
    local plugin="$1"
    
    [[ -d "$ZSH/plugins/$plugin" || -d "$ZSH_CUSTOM/plugins/$plugin" ]]
}

_omz_add_plugin() {
    local plugin="$1"
    
    if _omz_plugin_exists "$plugin"; then
        plugins+=("$plugin")
    fi
}

_omz_add_plugin git
_omz_add_plugin sudo
_omz_add_plugin fzf
_omz_add_plugin docker
_omz_add_plugin kubectl
_omz_add_plugin zsh-autosuggestions
_omz_add_plugin zsh-history-substring-search

# zsh-syntax-highlighting should be loaded last.
_omz_add_plugin zsh-syntax-highlighting

# -------------------------------------------------------------------
# Autosuggestions config
# -------------------------------------------------------------------
ZSH_AUTOSUGGEST_HIGHLIGHT_STYLE='fg=#6272A4'
ZSH_AUTOSUGGEST_STRATEGY=(history completion)

# -------------------------------------------------------------------
# Syntax highlighting config
# -------------------------------------------------------------------
ZSH_HIGHLIGHT_HIGHLIGHTERS=(main brackets pattern cursor)

# Dracula colors for zsh-syntax-highlighting.
# This must be loaded before zsh-syntax-highlighting itself is loaded by Oh My Zsh.
if [[ -r "${ZSH_CUSTOM:-$HOME/.oh-my-zsh/custom}/themes/dracula-zsh-syntax-highlighting/zsh-syntax-highlighting.sh" ]]; then
    source "${ZSH_CUSTOM:-$HOME/.oh-my-zsh/custom}/themes/dracula-zsh-syntax-highlighting/zsh-syntax-highlighting.sh"
fi

# -------------------------------------------------------------------
# Load Oh My Zsh
# -------------------------------------------------------------------
source "$ZSH/oh-my-zsh.sh"

# -------------------------------------------------------------------
# Load Powerlevel10k config
# -------------------------------------------------------------------
[[ -f "$HOME/.p10k.zsh" ]] && source "$HOME/.p10k.zsh"

# -------------------------------------------------------------------
# Key bindings
# -------------------------------------------------------------------
bindkey -e

# History substring search key bindings, if plugin is available.
if (( $+functions[history-substring-search-up] )); then
    bindkey '^[[A' history-substring-search-up
    bindkey '^P' history-substring-search-up
fi

if (( $+functions[history-substring-search-down] )); then
    bindkey '^[[B' history-substring-search-down
    bindkey '^N' history-substring-search-down
fi

# -------------------------------------------------------------------
# Helper functions
# -------------------------------------------------------------------
_has() {
    command -v "$1" >/dev/null 2>&1
}

_info() {
    print -P "%F{cyan}==>%f $*"
}

_warn() {
    print -P "%F{yellow}Warning:%f $*"
}

_error() {
    print -P "%F{red}Error:%f $*"
}

# -------------------------------------------------------------------
# Editor
# -------------------------------------------------------------------
if _has nvim; then
    export EDITOR="nvim"
    export VISUAL="nvim"
    alias vim="nvim"
else
    export EDITOR="${EDITOR:-vim}"
    export VISUAL="${VISUAL:-$EDITOR}"
fi

# -------------------------------------------------------------------
# ls / tree aliases
# -------------------------------------------------------------------
if _has eza; then
    alias ls='eza --icons --group-directories-first'
    alias ll='eza -la --icons --group-directories-first'
    alias la='eza -a --icons --group-directories-first'
    alias tree='eza --tree --icons'
else
    alias ls='ls --color=auto'
    alias ll='ls -la --color=auto'
    alias la='ls -a --color=auto'
    
    if _has tree; then
        alias tree='tree'
    fi
fi

# -------------------------------------------------------------------
# Navigation aliases
# Fish abbr equivalents
# -------------------------------------------------------------------
alias ..='cd ..'
alias ...='cd ../..'
alias ....='cd ../../..'
alias -- -='cd -'

# -------------------------------------------------------------------
# Git aliases
# -------------------------------------------------------------------
alias gst='git status'
alias gco='git checkout'
alias gcb='git checkout -b'
alias gp='git pull'
alias gps='git push'
alias ga='git add'
alias gaa='git add --all'
alias gc='git commit'
alias gcm='git commit -m'
alias gd='git diff'
alias gds='git diff --staged'
alias gl='git log --oneline --graph --decorate'
alias gla='git log --oneline --graph --decorate --all'
alias gb='git branch'
alias gba='git branch -a'
alias gr='git remote -v'

# -------------------------------------------------------------------
# Docker aliases
# -------------------------------------------------------------------
alias dps='docker ps'
alias dpsa='docker ps -a'
alias di='docker images'
alias dex='docker exec -it'
alias dlog='docker logs -f'
alias dstop='docker stop'
alias drm='docker rm'
alias drmi='docker rmi'
alias dc='docker compose'
alias dcu='docker compose up'
alias dcud='docker compose up -d'
alias dcd='docker compose down'
alias dcl='docker compose logs -f'

# -------------------------------------------------------------------
# Kubernetes aliases
# -------------------------------------------------------------------
alias k='kubectl'
alias kgp='kubectl get pods'
alias kgs='kubectl get svc'
alias kgd='kubectl get deploy'
alias kgn='kubectl get nodes'
alias kdp='kubectl describe pod'
alias kl='kubectl logs'
alias klf='kubectl logs -f'

# -------------------------------------------------------------------
# Generic aliases
# -------------------------------------------------------------------
alias grep='grep --color=auto'
alias ip='ip -c'
alias mkdir='mkdir -p'
alias reload-zsh='source ~/.zshrc'
alias zshconfig='$EDITOR ~/.zshrc'
alias p10kconfig='$EDITOR ~/.p10k.zsh'

# -------------------------------------------------------------------
# System update
# -------------------------------------------------------------------
update-system() {
    if ! _has apt; then
        _error "apt not found. This function is intended for Debian/Ubuntu-based systems."
        return 1
    fi
    
    _info "Updating system packages..."
    sudo apt update
    sudo apt upgrade -y
    sudo apt autoremove -y
    sudo apt autoclean
    _info "System update complete."
}

# -------------------------------------------------------------------
# Wordlist update
# -------------------------------------------------------------------
update-wordlists() {
    if ! _has git; then
        _error "git not found."
        return 1
    fi
    
    local wordlist_dirs=(
        "$HOME/wordlists/fuzzdb"
        "$HOME/wordlists/SecLists"
        "$HOME/wordlists/PayloadsAllTheThings"
        "$HOME/wordlists/Default-Accounts-Arsenal"
    )
    
    _info "Updating wordlists..."
    
    local dir
    for dir in "${wordlist_dirs[@]}"; do
        if [[ -d "$dir/.git" ]]; then
            _info "Updating $dir"
            git -C "$dir" pull --ff-only
            elif [[ -d "$dir" ]]; then
            _warn "$dir exists but is not a git repository."
        else
            _warn "$dir not found. Skipping."
        fi
    done
    
    _info "Wordlist update complete."
}

# -------------------------------------------------------------------
# Pentest tooling update
# -------------------------------------------------------------------
update-tools() {
    _info "Updating pentesting tools..."
    
    if _has go; then
        _info "Updating Go tools..."
        
        local go_tools=(
            "github.com/ffuf/ffuf/v2@latest"
            "github.com/projectdiscovery/httpx/cmd/httpx@latest"
            "github.com/projectdiscovery/subfinder/v2/cmd/subfinder@latest"
            "github.com/projectdiscovery/nuclei/v3/cmd/nuclei@latest"
            "github.com/projectdiscovery/katana/cmd/katana@latest"
            "github.com/projectdiscovery/naabu/v2/cmd/naabu@latest"
            "github.com/projectdiscovery/dnsx/cmd/dnsx@latest"
            "github.com/hahwul/dalfox/v2@latest"
            "github.com/tomnomnom/assetfinder@latest"
            "github.com/d3mondev/puredns/v2@latest"
            "github.com/owasp-amass/amass/v4/...@master"
            "github.com/jpillora/chisel@latest"
            "github.com/nicocha30/ligolo-ng/cmd/proxy@latest"
            "github.com/nicocha30/ligolo-ng/cmd/agent@latest"
            "github.com/BishopFox/cloudfox@latest"
            "github.com/gitleaks/gitleaks/v8@latest"
        )
        
        local tool
        for tool in "${go_tools[@]}"; do
            _info "go install $tool"
            go install "$tool"
        done
    else
        _warn "go not found. Skipping Go tools."
    fi
    
    if _has cargo; then
        _info "Updating Rust tools..."
        
        local rust_tools=(
            "feroxbuster"
            "rustscan"
            "rustcat"
            "rusthound"
            "eza"
        )
        
        local crate
        for crate in "${rust_tools[@]}"; do
            _info "cargo install $crate --force"
            cargo install "$crate" --force
        done
    else
        _warn "cargo not found. Skipping Rust tools."
    fi
    
    if _has pipx; then
        _info "Updating pipx tools..."
        pipx upgrade-all
    else
        _warn "pipx not found. Skipping pipx tools."
    fi
    
    if _has nuclei; then
        _info "Updating nuclei templates..."
        nuclei -update-templates
    else
        _warn "nuclei not found. Skipping nuclei template update."
    fi
    
    if _has apt; then
        _info "Updating system packages..."
        sudo apt update && sudo apt upgrade -y
    else
        _warn "apt not found. Skipping system package update."
    fi
    
    _info "Tools update complete."
}

# -------------------------------------------------------------------
# Python virtual environment activation helper
# -------------------------------------------------------------------
venv() {
    if [[ -f "./venv/bin/activate" ]]; then
        source "./venv/bin/activate"
        elif [[ -f "./.venv/bin/activate" ]]; then
        source "./.venv/bin/activate"
    else
        _warn "No virtual environment found in current directory."
        return 1
    fi
}

# -------------------------------------------------------------------
# Tools navigation
# -------------------------------------------------------------------
_tools_cd() {
    local target="$HOME/tools/$1"
    
    if [[ -d "$target" ]]; then
        cd "$target"
    else
        _warn "Directory not found: $target"
        return 1
    fi
}

toolsweb()     { _tools_cd "web"; }
toolsrecon()   { _tools_cd "recon"; }
toolsnetwork() { _tools_cd "network"; }
toolsexploit() { _tools_cd "exploit"; }
toolsad()      { _tools_cd "ad"; }
toolsprivesc() { _tools_cd "privesc"; }
toolsauto()    { _tools_cd "automation"; }
toolsosint()   { _tools_cd "osint"; }
toolscloud()   { _tools_cd "cloud"; }
toolsmisc()    { _tools_cd "misc"; }

# -------------------------------------------------------------------
# Convenience info
# -------------------------------------------------------------------
zsh-healthcheck() {
    _info "Shell: $SHELL"
    _info "Zsh version: $ZSH_VERSION"
    _info "Editor: $EDITOR"
    _info "GOPATH: $GOPATH"
    _info "PATH entries:"
    
    local entry
    for entry in "${path[@]}"; do
        print "  $entry"
    done
    
    print
    _info "Tool availability:"
    
    local tools=(
        git
        nvim
        eza
        go
        cargo
        pipx
        docker
        kubectl
        nuclei
        starship
    )
    
    local tool
    for tool in "${tools[@]}"; do
        if _has "$tool"; then
            print -P "  %F{green}OK%f  $tool -> $(command -v "$tool")"
        else
            print -P "  %F{red}NO%f  $tool"
        fi
    done
}
