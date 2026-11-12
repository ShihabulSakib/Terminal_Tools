#!/usr/bin/env bash
# ==============================================================================
# Cross-Platform Zsh & Powerlevel10k Universal Installer
# Compatible with: Fedora, Kali, Debian, Ubuntu, Arch Linux, openSUSE, Alpine, etc.
# ==============================================================================

set -eo pipefail

# ANSI color codes
BOLD="\033[1m"
GREEN="\033[0;32m"
BLUE="\033[0;34m"
YELLOW="\033[1;33m"
RED="\033[0;31m"
NC="\033[0m"

log_info()    { echo -e "${BLUE}${BOLD}[*]${NC} $1"; }
log_success() { echo -e "${GREEN}${BOLD}[✔]${NC} $1"; }
log_warn()    { echo -e "${YELLOW}${BOLD}[!]${NC} $1"; }
log_error()   { echo -e "${RED}${BOLD}[✘]${NC} $1" >&2; }

# Guard against executing the entire script as root via sudo (which corrupts $HOME ownership)
if [ "$EUID" -eq 0 ] && [ -n "${SUDO_USER:-}" ] && [ "$SUDO_USER" != "root" ]; then
    log_error "Please run this script as your regular user ($SUDO_USER), NOT with sudo."
    log_error "Example: ./install_zsh.sh"
    log_error "The script will automatically request sudo privileges only when installing system packages."
    exit 1
fi

# Determine privilege elevation tool for package installation
if [ "$EUID" -eq 0 ]; then
    SUDO=""
elif command -v sudo >/dev/null 2>&1; then
    SUDO="sudo"
elif command -v doas >/dev/null 2>&1; then
    SUDO="doas"
else
    log_error "Neither sudo nor doas is available to install system packages."
    log_error "Please install sudo, or run the package installation step as root first."
    exit 1
fi

# Detect Linux distribution and install prerequisite packages
detect_and_install_deps() {
    log_info "Detecting Linux distribution and package manager..."

    local os_id=""
    local os_like=""
    if [ -f /etc/os-release ]; then
        # shellcheck disable=SC1091
        . /etc/os-release
        os_id="${ID:-}"
        os_like="${ID_LIKE:-}"
    fi

    log_info "Detected OS: ${os_id:-unknown} (family: ${os_like:-none})"

    if command -v apt-get >/dev/null 2>&1; then
        log_info "Using apt-get (Debian / Ubuntu / Kali / Mint / Pop!_OS)..."
        $SUDO env DEBIAN_FRONTEND=noninteractive apt-get update -y
        $SUDO env DEBIAN_FRONTEND=noninteractive apt-get install -y \
            zsh git curl wget fontconfig tar gzip unzip procps
        # Optional command-not-found package
        $SUDO env DEBIAN_FRONTEND=noninteractive apt-get install -y command-not-found >/dev/null 2>&1 || true
    elif command -v dnf >/dev/null 2>&1; then
        log_info "Using dnf (Fedora / RHEL / CentOS / Rocky / AlmaLinux)..."
        $SUDO dnf install -y \
            zsh git curl wget fontconfig tar gzip unzip util-linux-user procps-ng
        # Optional command-not-found package
        $SUDO dnf install -y PackageKit-command-not-found >/dev/null 2>&1 || true
    elif command -v pacman >/dev/null 2>&1; then
        log_info "Using pacman (Arch Linux / Manjaro / EndeavourOS)..."
        $SUDO pacman -S --noconfirm --needed \
            zsh git curl wget fontconfig tar gzip unzip procps-ng
    elif command -v zypper >/dev/null 2>&1; then
        log_info "Using zypper (openSUSE)..."
        $SUDO zypper --non-interactive install \
            zsh git curl wget fontconfig tar gzip unzip
    elif command -v apk >/dev/null 2>&1; then
        log_info "Using apk (Alpine Linux)..."
        $SUDO apk add --no-cache \
            zsh git curl wget fontconfig tar gzip unzip shadow
    else
        log_warn "No recognized package manager found. Please ensure zsh, git, curl, and fontconfig are installed."
    fi
    log_success "System dependencies verified."
}

# Install MesloLGS NF fonts (official Powerlevel10k recommended Nerd Font)
install_nerd_fonts() {
    log_info "Installing MesloLGS NF fonts for Powerlevel10k glyphs..."
    local font_dir="$HOME/.local/share/fonts"
    mkdir -p "$font_dir"

    local base_url="https://github.com/romkatv/powerlevel10k-media/raw/master"
    local fonts=(
        "MesloLGS NF Regular.ttf"
        "MesloLGS NF Bold.ttf"
        "MesloLGS NF Italic.ttf"
        "MesloLGS NF Bold Italic.ttf"
    )

    local updated=0
    for font in "${fonts[@]}"; do
        local target_file="$font_dir/$font"
        # Download only if file is missing or empty (handles interrupted downloads)
        if [ ! -s "$target_file" ]; then
            log_info "Downloading $font..."
            local encoded_font="${font// /%20}"
            local tmp_font="${target_file}.tmp.$$"
            if curl -fsSL "$base_url/$encoded_font" -o "$tmp_font"; then
                mv -f "$tmp_font" "$target_file"
                updated=1
            else
                rm -f "$tmp_font"
                log_warn "Failed to download $font"
            fi
        else
            log_info "$font already present."
        fi
    done

    if [ "$updated" -eq 1 ] && command -v fc-cache >/dev/null 2>&1; then
        log_info "Updating system font cache..."
        fc-cache -f "$font_dir" >/dev/null 2>&1 || true
    fi
    log_success "Nerd fonts ready in $font_dir."
}

# Install Oh My Zsh unattended
install_oh_my_zsh() {
    if [ -d "$HOME/.oh-my-zsh/.git" ]; then
        log_info "Oh My Zsh is already installed at $HOME/.oh-my-zsh."
    else
        log_info "Installing Oh My Zsh..."
        [ -d "$HOME/.oh-my-zsh" ] && rm -rf "$HOME/.oh-my-zsh"
        RUNZSH=no CHSH=no KEEP_ZSHRC=yes sh -c "$(curl -fsSL https://raw.githubusercontent.com/ohmyzsh/ohmyzsh/master/tools/install.sh)" "" --unattended
        log_success "Oh My Zsh installed successfully."
    fi
}

# Install Powerlevel10k theme and custom plugins
install_theme_and_plugins() {
    local zsh_custom="${ZSH_CUSTOM:-$HOME/.oh-my-zsh/custom}"

    # 1. Powerlevel10k theme
    local p10k_dir="$zsh_custom/themes/powerlevel10k"
    if [ ! -d "$p10k_dir/.git" ]; then
        log_info "Cloning Powerlevel10k theme..."
        [ -d "$p10k_dir" ] && rm -rf "$p10k_dir"
        git clone --depth=1 https://github.com/romkatv/powerlevel10k.git "$p10k_dir"
    else
        log_info "Powerlevel10k theme already exists."
    fi

    # 2. Custom plugins
    mkdir -p "$zsh_custom/plugins"

    local plugins=(
        "zsh-syntax-highlighting|https://github.com/zsh-users/zsh-syntax-highlighting.git"
        "zsh-autosuggestions|https://github.com/zsh-users/zsh-autosuggestions.git"
        "zsh-completions|https://github.com/zsh-users/zsh-completions.git"
    )

    for item in "${plugins[@]}"; do
        local name="${item%%|*}"
        local url="${item##*|}"
        local dest="$zsh_custom/plugins/$name"
        if [ ! -d "$dest/.git" ]; then
            log_info "Cloning plugin: $name..."
            [ -d "$dest" ] && rm -rf "$dest"
            git clone --depth=1 "$url" "$dest"
        else
            log_info "Plugin $name already exists."
        fi
    done
    log_success "Themes and custom plugins ready."
}

# Install FZF via git for cross-distro compatibility with `fzf --zsh`
install_fzf() {
    local fzf_dir="$HOME/.fzf"
    if [ ! -d "$fzf_dir/.git" ]; then
        log_info "Cloning latest fzf repository..."
        [ -d "$fzf_dir" ] && rm -rf "$fzf_dir"
        git clone --depth 1 https://github.com/junegunn/fzf.git "$fzf_dir"
        "$fzf_dir/install" --bin --no-update-rc --no-bash --no-fish
    else
        log_info "fzf repository already exists at $fzf_dir."
        if [ ! -x "$fzf_dir/bin/fzf" ]; then
            "$fzf_dir/install" --bin --no-update-rc --no-bash --no-fish
        fi
    fi

    # Generate ~/.fzf.zsh with $HOME/.fzf/bin prepended
    log_info "Configuring ~/.fzf.zsh..."
    cat > "$HOME/.fzf.zsh" << 'EOF_FZF'
# Setup fzf
# ---------
if [[ ":$PATH:" != *":$HOME/.fzf/bin:"* ]]; then
  PATH="$HOME/.fzf/bin${PATH:+:${PATH}}"
fi

if command -v fzf >/dev/null 2>&1; then
  eval "$(fzf --zsh 2>/dev/null)" || true
fi
EOF_FZF
    log_success "fzf setup complete."
}

# Helper to backup existing config files only if content actually changed
backup_file() {
    local target="$1"
    local new_content_file="$2"
    if [ -f "$target" ]; then
        if [ -n "$new_content_file" ] && [ -f "$new_content_file" ]; then
            if cmp -s "$target" "$new_content_file"; then
                return 0
            fi
        fi
        local ts
        ts="$(date +%Y%m%d_%H%M%S)"
        cp "$target" "${target}.backup.${ts}"
        log_info "Backed up $(basename "$target") to $(basename "$target").backup.${ts}"
    fi
}

# Deploy Powerlevel10k configuration
deploy_p10k_config() {
    log_info "Deploying Powerlevel10k prompt configuration (~/.p10k.zsh)..."
    local tmp_p10k
    tmp_p10k="$(mktemp)"

    base64 -d << 'EOF_P10K_B64' | gunzip > "$tmp_p10k"
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
hZzAZ7xc5cn/D7wZfJKgdQEA
EOF_P10K_B64

    backup_file "$HOME/.p10k.zsh" "$tmp_p10k"
    mv -f "$tmp_p10k" "$HOME/.p10k.zsh"
    log_success "~/.p10k.zsh deployed."
}

# Deploy ~/.zshrc
deploy_zshrc() {
    log_info "Deploying ~/.zshrc..."
    local tmp_zshrc
    tmp_zshrc="$(mktemp)"

    cat > "$tmp_zshrc" << 'EOF_ZSHRC'
# ╔═══════════════════════════════════════════════════════════════════╗
# ║              ZSH Configuration with Powerlevel10k                 ║
# ╚═══════════════════════════════════════════════════════════════════╝

# Enable Powerlevel10k instant prompt (stays near top of ~/.zshrc)
if [[ -r "${XDG_CACHE_HOME:-$HOME/.cache}/p10k-instant-prompt-${(%):-%n}.zsh" ]]; then
  source "${XDG_CACHE_HOME:-$HOME/.cache}/p10k-instant-prompt-${(%):-%n}.zsh"
fi

# ZSH Configuration
export ZSH="$HOME/.oh-my-zsh"

# Set theme to Powerlevel10k
ZSH_THEME="powerlevel10k/powerlevel10k"

# Enable plugins
# Note: zsh-syntax-highlighting must be the LAST plugin in this list
plugins=(
    git
    zsh-completions
    zsh-autosuggestions
    python
    pip
    command-not-found
    extract
    z
    colored-man-pages
    zsh-syntax-highlighting
)

source $ZSH/oh-my-zsh.sh

# ╔═══════════════════════════════════════════════════════════════════╗
# ║                         User Configuration                        ║
# ╚═══════════════════════════════════════════════════════════════════╝

# Language settings
export LANG=en_US.UTF-8
export LC_ALL=en_US.UTF-8

# Editor configuration
export EDITOR=nano
export VISUAL=nano

# ╔═══════════════════════════════════════════════════════════════════╗
# ║                     Useful Aliases                                ║
# ╚═══════════════════════════════════════════════════════════════════╝

# Directory navigation
alias ..='cd ..'
alias ...='cd ../..'
alias ....='cd ../../..'
alias ll='ls -lah'
alias la='ls -la'
alias l='ls -lh'

# Git aliases
alias gst='git status'
alias ga='git add'
alias gaa='git add -A'
alias gc='git commit -m'
alias gp='git push'
alias gpl='git pull'
alias glog='git log --oneline -20'
alias gbr='git branch'
alias gch='git checkout'

# Utility aliases
alias cls='clear'
alias cp='cp -i'
alias mv='mv -i'
alias rm='rm -i'
alias mkdir='mkdir -p'
alias grep='grep --color=auto'

# Smart cross-distro system update alias
if command -v apt-get &>/dev/null; then
    alias update='sudo apt-get update && sudo apt-get upgrade -y'
elif command -v dnf &>/dev/null; then
    alias update='sudo dnf upgrade -y'
elif command -v pacman &>/dev/null; then
    alias update='sudo pacman -Syu'
elif command -v zypper &>/dev/null; then
    alias update='sudo zypper update -y'
elif command -v apk &>/dev/null; then
    alias update='sudo apk update && sudo apk upgrade'
fi

# ╔═══════════════════════════════════════════════════════════════════╗
# ║                  Advanced ZSH Settings                            ║
# ╚═══════════════════════════════════════════════════════════════════╝

# History settings
HISTFILE=~/.zsh_history
HISTSIZE=50000
SAVEHIST=50000
setopt SHARE_HISTORY
setopt HIST_FIND_NO_DUPS
setopt HIST_IGNORE_DUPS
setopt HIST_IGNORE_ALL_DUPS

# Completion settings
setopt MENU_COMPLETE

# Spelling correction
setopt CORRECT

# ╔═══════════════════════════════════════════════════════════════════╗
# ║                    FZF Configuration                              ║
# ╚═══════════════════════════════════════════════════════════════════╝

[ -f ~/.fzf.zsh ] && source ~/.fzf.zsh

# ╔═══════════════════════════════════════════════════════════════════╗
# ║                 Powerlevel10k Configuration                       ║
# ╚═══════════════════════════════════════════════════════════════════╝

# To customize prompt, run `p10k configure` or edit ~/.p10k.zsh
[[ ! -f ~/.p10k.zsh ]] || source ~/.p10k.zsh

# ╔═══════════════════════════════════════════════════════════════════╗
# ║                 Environment & Path Integrations                   ║
# ╚═══════════════════════════════════════════════════════════════════╝

# User bin directories
[ -d "$HOME/.local/bin" ] && export PATH="$HOME/.local/bin:$PATH"
[ -d "$HOME/bin" ] && export PATH="$HOME/bin:$PATH"

# Node Version Manager (NVM)
export NVM_DIR="$HOME/.nvm"
[ -s "$NVM_DIR/nvm.sh" ] && \. "$NVM_DIR/nvm.sh"
[ -s "$NVM_DIR/bash_completion" ] && \. "$NVM_DIR/bash_completion"

# Bun runtime
if [ -d "$HOME/.bun" ]; then
    [ -s "$HOME/.bun/_bun" ] && source "$HOME/.bun/_bun"
    export BUN_INSTALL="$HOME/.bun"
    [ -d "$BUN_INSTALL/bin" ] && export PATH="$BUN_INSTALL/bin:$PATH"
fi

# Go binaries
[ -d "/usr/local/go/bin" ] && export PATH="$PATH:/usr/local/go/bin"
[ -d "$HOME/go/bin" ] && export PATH="$PATH:$HOME/go/bin"
EOF_ZSHRC

    backup_file "$HOME/.zshrc" "$tmp_zshrc"
    mv -f "$tmp_zshrc" "$HOME/.zshrc"
    log_success "~/.zshrc deployed."
}

# Set default login shell to Zsh cleanly across distributions
set_default_shell() {
    local zsh_bin
    zsh_bin="$(command -v zsh || true)"
    if [ -z "$zsh_bin" ]; then
        log_error "zsh binary not found."
        return 1
    fi

    # Ensure zsh is listed in /etc/shells
    if [ -f /etc/shells ] && ! grep -qx "$zsh_bin" /etc/shells; then
        log_info "Registering $zsh_bin in /etc/shells..."
        echo "$zsh_bin" | $SUDO tee -a /etc/shells >/dev/null || true
    fi

    local target_user="${USER:-$(id -un)}"
    local current_shell=""

    if command -v getent >/dev/null 2>&1; then
        current_shell="$(getent passwd "$target_user" 2>/dev/null | cut -d: -f7 || true)"
    fi
    if [ -z "$current_shell" ] && [ -f /etc/passwd ]; then
        current_shell="$(awk -F: -v u="$target_user" '$1==u {print $7}' /etc/passwd 2>/dev/null || true)"
    fi
    current_shell="${current_shell:-$SHELL}"

    # Canonicalize paths (handles /bin vs /usr/bin symlinks)
    local real_current real_zsh
    real_current="$(readlink -f "$current_shell" 2>/dev/null || echo "$current_shell")"
    real_zsh="$(readlink -f "$zsh_bin" 2>/dev/null || echo "$zsh_bin")"

    if [ "$real_current" != "$real_zsh" ]; then
        log_info "Changing default shell to $zsh_bin for $target_user..."
        if [ -n "$SUDO" ]; then
            $SUDO chsh -s "$zsh_bin" "$target_user" 2>/dev/null || \
            $SUDO usermod -s "$zsh_bin" "$target_user" 2>/dev/null || \
            chsh -s "$zsh_bin" 2>/dev/null || \
            log_warn "Could not change shell automatically. You can run manually: chsh -s $zsh_bin"
        else
            chsh -s "$zsh_bin" 2>/dev/null || \
            log_warn "Could not change shell automatically. You can run manually: chsh -s $zsh_bin"
        fi
    else
        log_info "Default shell is already set to $zsh_bin."
    fi
}

main() {
    echo -e "${BOLD}======================================================${NC}"
    echo -e "${BOLD}  Universal Zsh + Powerlevel10k Installer & Sync      ${NC}"
    echo -e "${BOLD}======================================================${NC}"

    detect_and_install_deps
    install_nerd_fonts
    install_oh_my_zsh
    install_theme_and_plugins
    install_fzf
    deploy_p10k_config
    deploy_zshrc
    set_default_shell || log_warn "Default shell setting requires manual confirmation."

    echo ""
    echo -e "${GREEN}${BOLD}======================================================${NC}"
    echo -e "${GREEN}${BOLD}  Installation Complete! 🎉                           ${NC}"
    echo -e "${GREEN}${BOLD}======================================================${NC}"
    echo -e "Next steps:"
    echo -e "  1. Set your terminal font to ${BOLD}MesloLGS NF${NC} in your terminal preferences."
    echo -e "  2. Switch to zsh right now by running: ${BOLD}exec zsh${NC}"
    echo -e "  3. To reconfigure your prompt anytime, run: ${BOLD}p10k configure${NC}"
    echo ""
}

main "$@"
