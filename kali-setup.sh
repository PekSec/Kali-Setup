#!/usr/bin/env bash

################################################################################
# Kali Linux Complete Setup Script - soft-fail / self-healing refactor
# Author: Barış PEKALP
# Description: Automated setup for a pentesting environment
# Usage: sudo ./kali-setup.sh [path/to/cert.crt]
#
# Design goals:
# - Keep the original workflow order.
# - Do not fail-fast for individual tool/package failures.
# - Retry transient failures and attempt local self-healing.
# - Skip already-installed tools where safe.
# - Keep a structured error/warning summary at the end.
################################################################################

# No `set -e`: every operational failure is handled as a soft error.
# `pipefail` is kept so piped installers fail when any segment fails.
set -o pipefail
umask 022

################################################################################
# COLOR CODES
################################################################################
readonly RED='\033[0;31m'
readonly GREEN='\033[0;32m'
readonly YELLOW='\033[1;33m'
readonly BLUE='\033[0;34m'
readonly MAGENTA='\033[0;35m'
readonly CYAN='\033[0;36m'
readonly NC='\033[0m'
readonly BOLD='\033[1m'

################################################################################
# GLOBAL VARIABLES
################################################################################
SCRIPT_START_TIME=$(date +%s)
LOG_FILE="${LOG_FILE:-/tmp/kali-setup.log}"
ERROR_COUNT=0
WARNING_COUNT=0
SELF_HEAL_COUNT=0
SKIPPED_COUNT=0
CURRENT_STEP=0
CERT_FILE=""
ACTUAL_USER=""
ACTUAL_HOME=""
SOFT_ABORT=0
APT_UPDATED=0
FORCE_REINSTALL="${FORCE_REINSTALL:-0}"
DRY_RUN="${DRY_RUN:-0}"
PENTEST_YEAR="${PENTEST_YEAR:-$(date +%Y)}"
DOCKER_DEBIAN_SUITE="${DOCKER_DEBIAN_SUITE:-trixie}"
APT_INSTALL_RECOMMENDS="${APT_INSTALL_RECOMMENDS:-1}"
SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" >/dev/null 2>&1 && pwd -P || pwd)"

# Keep failures inspectable without terminating the run.
declare -a FAILED_ACTIONS=()
declare -a WARNING_ACTIONS=()

################################################################################
# LOGGING AND OUTPUT
################################################################################
q() {
    printf '%q' "$1"
}

log() {
    local message="$1"
    mkdir -p "$(dirname "$LOG_FILE")" 2>/dev/null || true
    echo -e "[$(date '+%Y-%m-%d %H:%M:%S')] $message" | tee -a "$LOG_FILE"
}

log_info() {
    echo -e "${BLUE}[INFO]${NC} $1" | tee -a "$LOG_FILE"
}

log_success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1" | tee -a "$LOG_FILE"
}

log_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1" | tee -a "$LOG_FILE"
    ((WARNING_COUNT++))
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $1" | tee -a "$LOG_FILE"
    ((ERROR_COUNT++))
}

section_header() {
    echo ""
    echo -e "${BOLD}${MAGENTA}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo -e "${BOLD}${MAGENTA} $1${NC}"
    echo -e "${BOLD}${MAGENTA}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo ""
}

progress() {
    ((CURRENT_STEP++))
    echo -e "${CYAN}[${CURRENT_STEP}]${NC} $1"
}

record_issue() {
    local severity="$1"
    local description="$2"
    local rc="$3"
    local command_text="$4"
    
    if [[ "$severity" == "warning" ]]; then
        log_warning "$description failed with rc=$rc"
        WARNING_ACTIONS+=("$description | rc=$rc | $command_text")
    else
        log_error "$description failed with rc=$rc"
        FAILED_ACTIONS+=("$description | rc=$rc | $command_text")
    fi
}

################################################################################
# USER / PRIVILEGE HANDLING
################################################################################
detect_user_context() {
    if [[ -n "${SUDO_USER:-}" && "${SUDO_USER:-}" != "root" ]]; then
        ACTUAL_USER="$SUDO_USER"
    else
        ACTUAL_USER="$(id -un 2>/dev/null || whoami)"
    fi
    
    ACTUAL_HOME="$(getent passwd "$ACTUAL_USER" 2>/dev/null | awk -F: '{print $6}')"
    if [[ -z "$ACTUAL_HOME" || ! -d "$ACTUAL_HOME" ]]; then
        ACTUAL_HOME="$(eval echo "~$ACTUAL_USER" 2>/dev/null)"
    fi
    if [[ -z "$ACTUAL_HOME" || ! -d "$ACTUAL_HOME" ]]; then
        ACTUAL_HOME="$HOME"
    fi
    
    LOG_FILE="${LOG_FILE:-$ACTUAL_HOME/kali-setup.log}"
    # If LOG_FILE was defaulted to /tmp before context detection, move it to user home.
    if [[ "$LOG_FILE" == "/tmp/kali-setup.log" && -n "$ACTUAL_HOME" ]]; then
        LOG_FILE="$ACTUAL_HOME/kali-setup.log"
    fi
    
    touch "$LOG_FILE" 2>/dev/null || LOG_FILE="/tmp/kali-setup.log"
    if [[ $EUID -eq 0 ]]; then
        chown "$ACTUAL_USER:$ACTUAL_USER" "$LOG_FILE" 2>/dev/null || true
    fi
}

check_privileges() {
    section_header "Checking Privileges"
    detect_user_context
    
    if [[ $EUID -ne 0 ]]; then
        if command -v sudo >/dev/null 2>&1; then
            log_warning "Script is not running as root; attempting self-heal by re-executing via sudo"
            exec sudo -E bash "$0" "$@"
        fi
        
        record_issue "error" "Root privileges unavailable and sudo not found" 1 "sudo -E bash $0"
        SOFT_ABORT=1
        return 0
    fi
    
    log_success "Running as root with actual user: $ACTUAL_USER"
    log_info "User home directory: $ACTUAL_HOME"
    log_info "Log file: $LOG_FILE"
}

parse_arguments() {
    if [[ $# -gt 0 ]]; then
        CERT_FILE="$1"
        log_info "Certificate file provided: $CERT_FILE"
    fi
}

################################################################################
# COMMAND EXECUTION / SELF-HEALING
################################################################################
wait_for_apt_locks() {
    local locks=(
        /var/lib/dpkg/lock
        /var/lib/dpkg/lock-frontend
        /var/lib/apt/lists/lock
        /var/cache/apt/archives/lock
    )
    local waited=0
    local max_wait=180
    
    while true; do
        local busy=0
        local lock
        for lock in "${locks[@]}"; do
            if [[ -e "$lock" ]] && fuser "$lock" >/dev/null 2>&1; then
                busy=1
                break
            fi
        done
        
        if [[ $busy -eq 0 ]]; then
            return 0
        fi
        
        if (( waited >= max_wait )); then
            return 1
        fi
        
        log_warning "APT/dpkg lock is busy; waiting 5 seconds"
        sleep 5
        waited=$((waited + 5))
    done
}

apt_repair() {
    log_warning "Attempting APT/dpkg self-heal"
    ((SELF_HEAL_COUNT++))
    
    wait_for_apt_locks || log_warning "APT lock wait timed out; continuing with repair attempt"
    DEBIAN_FRONTEND=noninteractive dpkg --configure -a >>"$LOG_FILE" 2>&1 || true
    DEBIAN_FRONTEND=noninteractive apt-get -f install -y >>"$LOG_FILE" 2>&1 || true
    apt-get clean >>"$LOG_FILE" 2>&1 || true
}

self_heal() {
    local command_text="$1"
    local rc="$2"
    
    case "$command_text" in
        *apt-get*|*apt\ *|*dpkg*)
            apt_repair
        ;;
        *go\ install*)
            log_warning "Attempting Go environment self-heal after rc=$rc"
            ((SELF_HEAL_COUNT++))
            DEBIAN_FRONTEND=noninteractive apt-get install -y golang-go >>"$LOG_FILE" 2>&1 || true
        ;;
        *cargo\ install*|*rustup.rs*)
            log_warning "Attempting Rust/Cargo environment self-heal after rc=$rc"
            ((SELF_HEAL_COUNT++))
            if [[ -n "$ACTUAL_USER" ]]; then
                runuser -u "$ACTUAL_USER" -- env HOME="$ACTUAL_HOME" bash -lc 'curl --proto "=https" --tlsv1.2 -sSf https://sh.rustup.rs | sh -s -- -y' >>"$LOG_FILE" 2>&1 || true
            fi
        ;;
        *pipx*)
            log_warning "Attempting pipx environment self-heal after rc=$rc"
            ((SELF_HEAL_COUNT++))
            DEBIAN_FRONTEND=noninteractive apt-get install -y pipx python3-venv python3-pip >>"$LOG_FILE" 2>&1 || true
            if [[ -n "$ACTUAL_USER" ]]; then
                runuser -u "$ACTUAL_USER" -- env HOME="$ACTUAL_HOME" bash -lc 'python3 -m pipx ensurepath || pipx ensurepath' >>"$LOG_FILE" 2>&1 || true
            fi
        ;;
        *systemctl*)
            log_warning "Attempting systemd daemon-reload after rc=$rc"
            ((SELF_HEAL_COUNT++))
            systemctl daemon-reload >>"$LOG_FILE" 2>&1 || true
        ;;
        *git\ clone*|*git\ -C*)
            log_warning "Git operation failed; retry may recover transient network/repository state"
            ((SELF_HEAL_COUNT++))
        ;;
        *)
            return 0
        ;;
    esac
}

exec_cmd() {
    local description="$1"
    local attempts="$2"
    local command_text="$3"
    local attempt=1
    local rc=0
    
    if [[ "$DRY_RUN" == "1" ]]; then
        log_info "DRY_RUN: $description :: $command_text"
        return 0
    fi
    
    while (( attempt <= attempts )); do
        log_info "Running: $description (attempt $attempt/$attempts)"
        log "CMD: $command_text"
        
        if [[ "$command_text" == *apt-get* || "$command_text" == *dpkg* ]]; then
            wait_for_apt_locks || log_warning "APT lock wait timed out before: $description"
        fi
        
        bash -o pipefail -c "$command_text" >>"$LOG_FILE" 2>&1
        rc=$?
        
        if [[ $rc -eq 0 ]]; then
            log_success "$description"
            return 0
        fi
        
        log_warning "$description failed on attempt $attempt/$attempts with rc=$rc"
        self_heal "$command_text" "$rc" || true
        
        if (( attempt < attempts )); then
            sleep $((attempt * 2))
        fi
        ((attempt++))
    done
    
    return "$rc"
}

run_cmd() {
    local description="$1"
    local severity="$2"
    local attempts="$3"
    local command_text="$4"
    
    progress "$description"
    if exec_cmd "$description" "$attempts" "$command_text"; then
        return 0
    fi
    
    local rc=$?
    record_issue "$severity" "$description" "$rc" "$command_text"
    return 0
}

run_as_user_cmd() {
    local description="$1"
    local severity="$2"
    local attempts="$3"
    local user_command="$4"
    local user_q home_q command_q
    
    user_q="$(q "$ACTUAL_USER")"
    home_q="$(q "$ACTUAL_HOME")"
    command_q="$(q "export HOME=$ACTUAL_HOME; export GOPATH=\"\$HOME/go\"; export PATH=\"\$HOME/.local/bin:\$HOME/go/bin:\$HOME/.cargo/bin:/usr/local/go/bin:\$PATH\"; [[ -f \"\$HOME/.cargo/env\" ]] && source \"\$HOME/.cargo/env\"; $user_command")"
    
    run_cmd "$description" "$severity" "$attempts" "runuser -u $user_q -- env HOME=$home_q bash -lc $command_q"
}

user_cmd_exists() {
    local binary="$1"
    runuser -u "$ACTUAL_USER" -- env HOME="$ACTUAL_HOME" bash -lc "export PATH=\"\$HOME/.local/bin:\$HOME/go/bin:\$HOME/.cargo/bin:/usr/local/go/bin:\$PATH\"; command -v $(q "$binary")" >>"$LOG_FILE" 2>&1
}

root_cmd_exists() {
    command -v "$1" >/dev/null 2>&1
}

mark_skipped() {
    local message="$1"
    ((SKIPPED_COUNT++))
    progress "$message"
    log_success "$message - already satisfied, skipping"
}

################################################################################
# APT HELPERS
################################################################################
apt_update_once() {
    if [[ "$APT_UPDATED" == "1" ]]; then
        log_info "APT package lists already updated in this run; skipping duplicate update"
        return 0
    fi
    
    progress "Updating package lists"
    if exec_cmd "Updating package lists" 3 "DEBIAN_FRONTEND=noninteractive apt-get update"; then
        APT_UPDATED=1
        return 0
    fi
    
    local rc=$?
    record_issue "error" "Updating package lists" "$rc" "apt-get update"
    return 0
}

is_pkg_installed() {
    local pkg="$1"
    dpkg-query -W -f='${db:Status-Abbrev}' "$pkg" 2>/dev/null | grep -q '^ii'
}

apt_install_packages() {
    local description="$1"
    shift
    local packages=("$@")
    local missing=()
    local pkg
    
    for pkg in "${packages[@]}"; do
        if ! is_pkg_installed "$pkg"; then
            missing+=("$pkg")
        fi
    done
    
    if [[ ${#missing[@]} -eq 0 ]]; then
        mark_skipped "$description"
        return 0
    fi
    
    local opts="-y -o Dpkg::Options::=--force-confdef -o Dpkg::Options::=--force-confold"
    if [[ "$APT_INSTALL_RECOMMENDS" == "0" ]]; then
        opts="$opts --no-install-recommends"
    fi
    
    local quoted_packages=""
    for pkg in "${missing[@]}"; do
        quoted_packages+=" $(q "$pkg")"
    done
    
    run_cmd "$description" "error" 3 "DEBIAN_FRONTEND=noninteractive apt-get install $opts $quoted_packages"
}

################################################################################
# INSTALL HELPERS
################################################################################
clone_or_update_repo() {
    local description="$1"
    local repo="$2"
    local target="$3"
    local depth="${4:-1}"
    local parent backup
    
    if [[ "$DRY_RUN" == "1" ]]; then
        progress "$description"
        log_info "DRY_RUN: would clone/update $repo -> $target"
        return 0
    fi
    
    parent="$(dirname "$target")"
    mkdir -p "$parent" 2>/dev/null || true
    chown -R "$ACTUAL_USER:$ACTUAL_USER" "$parent" 2>/dev/null || true
    
    if [[ -d "$target/.git" ]]; then
        chown -R "$ACTUAL_USER:$ACTUAL_USER" "$target" 2>/dev/null || true
        run_as_user_cmd "$description - updating existing repository" "warning" 2 "git -C $(q "$target") pull --ff-only --depth $(q "$depth")"
        return 0
    fi
    
    if [[ -e "$target" ]]; then
        backup="${target}.backup.$(date +%Y%m%d%H%M%S)"
        run_cmd "$description - backing up non-git target" "warning" 1 "mv $(q "$target") $(q "$backup")"
        chown -R "$ACTUAL_USER:$ACTUAL_USER" "$backup" 2>/dev/null || true
    fi
    
    run_as_user_cmd "$description" "error" 2 "git clone --depth $(q "$depth") $(q "$repo") $(q "$target")"
    chown -R "$ACTUAL_USER:$ACTUAL_USER" "$target" 2>/dev/null || true
}
install_go_tool() {
    local description="$1"
    local binary="$2"
    local module="$3"
    
    if [[ "$FORCE_REINSTALL" != "1" ]] && user_cmd_exists "$binary"; then
        mark_skipped "$description"
        return 0
    fi
    
    run_as_user_cmd "$description" "error" 2 "go install $(q "$module")"
}

install_cargo_tool() {
    local description="$1"
    local binary="$2"
    local crate="$3"
    
    if [[ "$FORCE_REINSTALL" != "1" ]] && user_cmd_exists "$binary"; then
        mark_skipped "$description"
        return 0
    fi
    
    run_as_user_cmd "$description" "error" 2 "cargo install $(q "$crate")"
}

install_pipx_tool() {
    local description="$1"
    local binary="$2"
    local package_spec="$3"
    
    if [[ "$FORCE_REINSTALL" != "1" ]] && user_cmd_exists "$binary"; then
        mark_skipped "$description"
        return 0
    fi
    
    run_as_user_cmd "$description" "error" 2 "python3 -m pipx install $(q "$package_spec") || pipx install $(q "$package_spec")"
}

install_pip_requirements_repo() {
    local description="$1"
    local repo="$2"
    local target="$3"
    local entry_file="${4:-}"
    
    clone_or_update_repo "$description - repository" "$repo" "$target" 1
    
    local install_cmd="cd $(q "$target") && python3 -m pip install --user -r requirements.txt"
    run_as_user_cmd "$description - Python requirements" "warning" 2 "$install_cmd"
    
    if [[ -n "$entry_file" ]]; then
        run_as_user_cmd "$description - executable bit" "warning" 1 "chmod +x $(q "$target/$entry_file") 2>/dev/null || true"
    fi
}

################################################################################
# CERTIFICATE MANAGEMENT
################################################################################
install_certificate() {
    section_header "Certificate Management"
    
    if [[ -z "$CERT_FILE" ]]; then
        log_warning "No certificate file provided, skipping certificate installation"
        return 0
    fi
    
    if [[ ! -f "$CERT_FILE" ]]; then
        record_issue "warning" "Certificate file not found" 1 "$CERT_FILE"
        return 0
    fi
    
    local cert_name cert_target
    cert_name="$(basename "$CERT_FILE")"
    cert_target="/usr/local/share/ca-certificates/$cert_name"
    
    run_cmd "Installing custom certificate" "warning" 2 "cp $(q "$CERT_FILE") $(q "$cert_target") && update-ca-certificates"
}

################################################################################
# SYSTEM UPDATE
################################################################################
install_openjdk() {
    progress "Installing OpenJDK"
    if is_pkg_installed openjdk-21-jdk || is_pkg_installed openjdk-17-jdk; then
        log_success "OpenJDK already installed"
        ((SKIPPED_COUNT++))
        return 0
    fi
    
    if exec_cmd "Installing OpenJDK 21" 2 "DEBIAN_FRONTEND=noninteractive apt-get install -y openjdk-21-jdk"; then
        return 0
    fi
    
    log_warning "OpenJDK 21 installation failed; trying OpenJDK 17 fallback"
    if exec_cmd "Installing OpenJDK 17 fallback" 2 "DEBIAN_FRONTEND=noninteractive apt-get install -y openjdk-17-jdk"; then
        return 0
    fi
    
    local rc=$?
    record_issue "error" "Installing OpenJDK" "$rc" "apt-get install openjdk-21-jdk || openjdk-17-jdk"
}

install_nodesource() {
    progress "Installing Node.js for BloodHound"
    if root_cmd_exists node; then
        log_success "Node.js already available"
        ((SKIPPED_COUNT++))
        return 0
    fi
    
    if exec_cmd "Adding NodeSource repository" 2 "curl -fsSL https://deb.nodesource.com/setup_20.x | bash -"; then
        apt_install_packages "Installing Node.js" nodejs
        return 0
    fi
    
    log_warning "NodeSource setup failed; trying distro nodejs package"
    apt_install_packages "Installing distro Node.js fallback" nodejs npm
}

update_system() {
    section_header "System Update & Basic Packages"
    
    apt_update_once
    run_cmd "Upgrading system packages" "warning" 2 "DEBIAN_FRONTEND=noninteractive apt-get upgrade -y"
    
    apt_install_packages "Installing basic tools" git wget curl vim ca-certificates gnupg lsb-release fzf jq unzip p7zip-full
    apt_install_packages "Installing modern CLI tools" bat fd-find ripgrep tmux btop
    install_openjdk
    apt_install_packages "Installing build tools" build-essential make gcc g++ pkg-config libssl-dev
    install_nodesource
    
    log_success "System update completed"
}

################################################################################
# SHELL INSTALLATION
################################################################################
install_shell() {
    section_header "Shell Installation"
    
    apt_install_packages "Installing zsh shell" zsh
    
    log_success "Shell tools installed"
}

################################################################################
# DEVELOPMENT TOOLS
################################################################################
write_docker_source() {
    local suite="$1"
    if [[ "$DRY_RUN" == "1" ]]; then
        log_info "DRY_RUN: would write Docker repository source for suite: $suite"
        return 0
    fi
    install -m 0755 -d /etc/apt/keyrings >>"$LOG_FILE" 2>&1 || true
    cat > /etc/apt/sources.list.d/docker.sources <<EOFDOCKER
Types: deb
URIs: https://download.docker.com/linux/debian
Suites: $suite
Components: stable
Signed-By: /etc/apt/keyrings/docker.asc
EOFDOCKER
}

install_docker() {
    progress "Removing old Docker packages"
    exec_cmd "Removing old Docker packages" 1 "DEBIAN_FRONTEND=noninteractive apt-get remove -y docker.io docker-compose docker-doc podman-docker containerd runc" || true
    
    apt_install_packages "Installing Docker prerequisites" ca-certificates curl gnupg
    run_cmd "Setting up Docker GPG key" "error" 3 "install -m 0755 -d /etc/apt/keyrings && curl -fsSL https://download.docker.com/linux/debian/gpg -o /etc/apt/keyrings/docker.asc && chmod a+r /etc/apt/keyrings/docker.asc"
    
    progress "Adding Docker repository"
    write_docker_source "$DOCKER_DEBIAN_SUITE"
    log_success "Docker repository configured for Debian suite: $DOCKER_DEBIAN_SUITE"
    
    APT_UPDATED=0
    progress "Updating package lists for Docker repository"
    if ! exec_cmd "Updating package lists for Docker repository" 2 "DEBIAN_FRONTEND=noninteractive apt-get update"; then
        log_warning "Docker repo update failed for $DOCKER_DEBIAN_SUITE; trying bookworm fallback"
        write_docker_source "bookworm"
        exec_cmd "Updating package lists for Docker bookworm fallback" 2 "DEBIAN_FRONTEND=noninteractive apt-get update" || record_issue "warning" "Docker repository update" "$?" "apt-get update docker repo"
    fi
    APT_UPDATED=1
    
    apt_install_packages "Installing Docker CE and plugins" docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin
    run_cmd "Enabling Docker service" "warning" 2 "systemctl enable --now docker"
    run_cmd "Adding user to docker group" "warning" 1 "usermod -aG docker $(q "$ACTUAL_USER")"
}

install_rust() {
    if user_cmd_exists cargo; then
        mark_skipped "Installing Rust for user"
    else
        run_as_user_cmd "Installing Rust for user" "error" 2 "curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | sh -s -- -y"
    fi
    
    if root_cmd_exists cargo; then
        mark_skipped "Installing Rust for root"
    else
        run_cmd "Installing Rust for root" "warning" 2 "curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | sh -s -- -y"
    fi
    
    run_as_user_cmd "Verifying Rust environment" "warning" 1 "cargo --version"
}

install_dev_tools() {
    section_header "Development Tools Installation"
    
    apt_install_packages "Installing Python development tools" python3-full python3-pip python3-venv
    apt_install_packages "Installing pipx" pipx
    run_as_user_cmd "Ensuring pipx PATH for user" "warning" 1 "python3 -m pipx ensurepath || pipx ensurepath"
    
    install_docker
    
    apt_install_packages "Installing Go" golang-go
    run_as_user_cmd "Preparing Go workspace" "warning" 1 "mkdir -p \"\$HOME/go/bin\""
    
    install_rust
    
    if root_cmd_exists eza || user_cmd_exists eza; then
        mark_skipped "Installing eza modern ls"
    else
        progress "Installing eza modern ls"
        if exec_cmd "Installing eza via APT" 1 "DEBIAN_FRONTEND=noninteractive apt-get install -y eza"; then
            log_success "eza installed via APT"
        else
            log_warning "eza not available via APT; trying cargo fallback"
            install_cargo_tool "Installing eza via cargo" eza eza
        fi
    fi
    
    log_success "Development tools installed"
}

################################################################################
# SHELL CONFIGURATION
################################################################################
install_zsh_repo_for_user() {
    local description="$1"
    local repo="$2"
    local target="$3"
    local parent="${target%/*}"
    
    run_as_user_cmd "$description for user" "warning" 2 "mkdir -p \"$parent\" && if [[ -d \"$target/.git\" ]]; then git -C \"$target\" pull --ff-only; elif [[ -e \"$target\" ]]; then mv \"$target\" \"$target.backup.\$(date +%Y%m%d%H%M%S)\" && git clone --depth 1 \"$repo\" \"$target\"; else git clone --depth 1 \"$repo\" \"$target\"; fi"
}

install_zsh_repo_for_root() {
    local description="$1"
    local repo="$2"
    local target="$3"
    local parent="${target%/*}"
    
    run_cmd "$description for root" "warning" 2 "mkdir -p $(q "$parent") && if [[ -d $(q "$target/.git") ]]; then git -C $(q "$target") pull --ff-only; elif [[ -e $(q "$target") ]]; then mv $(q "$target") $(q "$target").backup.\$(date +%Y%m%d%H%M%S) && git clone --depth 1 $(q "$repo") $(q "$target"); else git clone --depth 1 $(q "$repo") $(q "$target"); fi"
}

install_zsh_stack_for_user() {
    install_zsh_repo_for_user "Installing Oh My Zsh" "https://github.com/ohmyzsh/ohmyzsh.git" "\$HOME/.oh-my-zsh"
    install_zsh_repo_for_user "Installing Powerlevel10k" "https://github.com/romkatv/powerlevel10k.git" "\$HOME/.oh-my-zsh/custom/themes/powerlevel10k"
    install_zsh_repo_for_user "Installing zsh-autosuggestions" "https://github.com/zsh-users/zsh-autosuggestions.git" "\$HOME/.oh-my-zsh/custom/plugins/zsh-autosuggestions"
    install_zsh_repo_for_user "Installing zsh-history-substring-search" "https://github.com/zsh-users/zsh-history-substring-search.git" "\$HOME/.oh-my-zsh/custom/plugins/zsh-history-substring-search"
    install_zsh_repo_for_user "Installing zsh-syntax-highlighting" "https://github.com/zsh-users/zsh-syntax-highlighting.git" "\$HOME/.oh-my-zsh/custom/plugins/zsh-syntax-highlighting"
    install_zsh_repo_for_user "Installing Dracula zsh syntax colors" "https://github.com/dracula/zsh-syntax-highlighting.git" "\$HOME/.oh-my-zsh/custom/themes/dracula-zsh-syntax-highlighting"
}

install_zsh_stack_for_root() {
    install_zsh_repo_for_root "Installing Oh My Zsh" "https://github.com/ohmyzsh/ohmyzsh.git" "/root/.oh-my-zsh"
    install_zsh_repo_for_root "Installing Powerlevel10k" "https://github.com/romkatv/powerlevel10k.git" "/root/.oh-my-zsh/custom/themes/powerlevel10k"
    install_zsh_repo_for_root "Installing zsh-autosuggestions" "https://github.com/zsh-users/zsh-autosuggestions.git" "/root/.oh-my-zsh/custom/plugins/zsh-autosuggestions"
    install_zsh_repo_for_root "Installing zsh-history-substring-search" "https://github.com/zsh-users/zsh-history-substring-search.git" "/root/.oh-my-zsh/custom/plugins/zsh-history-substring-search"
    install_zsh_repo_for_root "Installing zsh-syntax-highlighting" "https://github.com/zsh-users/zsh-syntax-highlighting.git" "/root/.oh-my-zsh/custom/plugins/zsh-syntax-highlighting"
    install_zsh_repo_for_root "Installing Dracula zsh syntax colors" "https://github.com/dracula/zsh-syntax-highlighting.git" "/root/.oh-my-zsh/custom/themes/dracula-zsh-syntax-highlighting"
}

install_zshrc_file() {
    local description="$1"
    local home_dir="$2"
    local owner="$3"
    local group="$4"
    local source_file="$SCRIPT_DIR/.zshrc"
    local target_file="$home_dir/.zshrc"
    local backup_file
    
    progress "$description"
    
    if [[ "$DRY_RUN" == "1" ]]; then
        log_info "DRY_RUN: would copy $source_file -> $target_file"
        return 0
    fi
    
    if [[ ! -f "$source_file" ]]; then
        record_issue "warning" "$description skipped because source .zshrc is missing" 1 "$source_file"
        return 0
    fi
    
    mkdir -p "$home_dir" 2>/dev/null || true
    
    if [[ -f "$target_file" ]] && cmp -s "$source_file" "$target_file"; then
        log_success "$description - already current"
        ((SKIPPED_COUNT++))
        return 0
    fi
    
    if [[ -e "$target_file" ]]; then
        backup_file="$target_file.backup.$(date +%Y%m%d%H%M%S)"
        if cp -a "$target_file" "$backup_file"; then
            chown "$owner:$group" "$backup_file" 2>/dev/null || true
            log_info "Backed up existing $target_file to $backup_file"
        else
            record_issue "warning" "Backing up existing $target_file" 1 "cp -a $target_file $backup_file"
        fi
    fi
    
    if cp "$source_file" "$target_file"; then
        chown "$owner:$group" "$target_file" 2>/dev/null || true
        chmod 0644 "$target_file" 2>/dev/null || true
        log_success "$description"
    else
        record_issue "error" "$description" 1 "cp $source_file $target_file"
    fi
}

configure_shell() {
    section_header "Shell Configuration"
    
    local zsh_path="/usr/bin/zsh"
    local actual_group
    
    if command -v zsh >/dev/null 2>&1; then
        zsh_path="$(command -v zsh)"
    fi
    
    actual_group="$(id -gn "$ACTUAL_USER" 2>/dev/null || echo "$ACTUAL_USER")"
    
    run_cmd "Ensuring zsh is listed in /etc/shells" "warning" 1 "grep -qxF $(q "$zsh_path") /etc/shells || echo $(q "$zsh_path") >> /etc/shells"
    run_cmd "Changing user shell to zsh" "warning" 1 "chsh -s $(q "$zsh_path") $(q "$ACTUAL_USER")"
    run_cmd "Changing root shell to zsh" "warning" 1 "chsh -s $(q "$zsh_path") root"
    
    install_zsh_stack_for_user
    install_zsh_stack_for_root
    install_zshrc_file "Installing .zshrc for user" "$ACTUAL_HOME" "$ACTUAL_USER" "$actual_group"
    install_zshrc_file "Installing .zshrc for root" "/root" "root" "root"
    
    log_success "Shell configuration completed"
}

################################################################################
# DIRECTORY STRUCTURE
################################################################################
create_directory_structure() {
    section_header "Creating Directory Structure"
    
    run_as_user_cmd "Creating pentesting directories" "error" 1 "mkdir -p \"\$HOME/wordlists\" \"\$HOME/pentests\" \"\$HOME/tools\"/{web,recon,network,exploit,ad,privesc,automation,osint,cloud,misc}"
    run_as_user_cmd "Creating monthly pentest directories" "warning" 1 "for m in \$(seq -f '%02g' 1 12); do mkdir -p \"\$HOME/pentests/$PENTEST_YEAR.\$m\"; done"
    run_cmd "Setting proper permissions" "warning" 1 "find $(q "$ACTUAL_HOME/tools") $(q "$ACTUAL_HOME/wordlists") $(q "$ACTUAL_HOME/pentests") -type d -exec chmod 755 {} + 2>/dev/null || true"
    
    log_success "Directory structure created"
}

################################################################################
# WORDLIST REPOSITORIES
################################################################################
clone_wordlists() {
    section_header "Cloning Wordlist Repositories"
    
    run_cmd "Removing seclists package if installed" "warning" 1 "DEBIAN_FRONTEND=noninteractive apt-get remove -y seclists"
    clone_or_update_repo "Cloning fuzzdb" "https://github.com/fuzzdb-project/fuzzdb.git" "$ACTUAL_HOME/wordlists/fuzzdb" 1
    clone_or_update_repo "Cloning SecLists" "https://github.com/danielmiessler/SecLists.git" "$ACTUAL_HOME/wordlists/SecLists" 1
    clone_or_update_repo "Cloning PayloadsAllTheThings" "https://github.com/swisskyrepo/PayloadsAllTheThings.git" "$ACTUAL_HOME/wordlists/PayloadsAllTheThings" 1
    clone_or_update_repo "Cloning Default-Accounts-Arsenal" "https://github.com/PekSec/Default-Accounts-Arsenal.git" "$ACTUAL_HOME/wordlists/Default-Accounts-Arsenal" 1
    run_cmd "Fixing wordlist ownership" "warning" 1 "chown -R $(q "$ACTUAL_USER:$ACTUAL_USER") $(q "$ACTUAL_HOME/wordlists")"
    
    log_success "Wordlist repositories processed"
}

################################################################################
# WEB TOOLS
################################################################################
install_web_tools() {
    section_header "Installing Web Application Security Tools"
    
    install_go_tool "Installing ffuf" ffuf "github.com/ffuf/ffuf/v2@latest"
    install_go_tool "Installing httpx" httpx "github.com/projectdiscovery/httpx/cmd/httpx@latest"
    install_go_tool "Installing katana" katana "github.com/projectdiscovery/katana/cmd/katana@latest"
    install_go_tool "Installing nuclei" nuclei "github.com/projectdiscovery/nuclei/v3/cmd/nuclei@latest"
    install_go_tool "Installing dalfox" dalfox "github.com/hahwul/dalfox/v2@latest"
    
    install_cargo_tool "Installing feroxbuster" feroxbuster feroxbuster
    
    install_pip_requirements_repo "Installing XSStrike" "https://github.com/s0md3v/XSStrike.git" "$ACTUAL_HOME/tools/web/XSStrike" "xsstrike.py"
    install_pipx_tool "Installing Arjun" arjun arjun
    install_pip_requirements_repo "Installing Corsy" "https://github.com/s0md3v/Corsy.git" "$ACTUAL_HOME/tools/web/Corsy" "corsy.py"
    
    apt_install_packages "Installing sqlmap" sqlmap
    
    log_success "Web tools installed"
}

################################################################################
# RECON TOOLS
################################################################################
install_recon_tools() {
    section_header "Installing Reconnaissance & Enumeration Tools"
    
    install_go_tool "Installing subfinder" subfinder "github.com/projectdiscovery/subfinder/v2/cmd/subfinder@latest"
    install_go_tool "Installing assetfinder" assetfinder "github.com/tomnomnom/assetfinder@latest"
    install_go_tool "Installing amass" amass "github.com/owasp-amass/amass/v4/...@master"
    install_go_tool "Installing puredns" puredns "github.com/d3mondev/puredns/v2@latest"
    install_go_tool "Installing dnsx" dnsx "github.com/projectdiscovery/dnsx/cmd/dnsx@latest"
    install_go_tool "Installing naabu" naabu "github.com/projectdiscovery/naabu/v2/cmd/naabu@latest"
    install_cargo_tool "Installing rustscan" rustscan rustscan
    
    log_success "Recon tools installed"
}

################################################################################
# NETWORK TOOLS
################################################################################
install_network_tools() {
    section_header "Installing Network Analysis & Pivoting Tools"
    
    install_go_tool "Installing chisel" chisel "github.com/jpillora/chisel@latest"
    install_go_tool "Installing ligolo-ng proxy" proxy "github.com/nicocha30/ligolo-ng/cmd/proxy@latest"
    install_go_tool "Installing ligolo-ng agent" agent "github.com/nicocha30/ligolo-ng/cmd/agent@latest"
    install_cargo_tool "Installing rustcat" rustcat rustcat
    
    log_success "Network tools installed"
}

################################################################################
# EXPLOITATION TOOLS
################################################################################
install_exploit_tools() {
    section_header "Installing Exploitation & C2 Frameworks"
    
    progress "Installing Sliver C2 Framework"
    local user_q home_q sliver_target
    user_q="$(q "$ACTUAL_USER")"
    home_q="$(q "$ACTUAL_HOME")"
    sliver_target="$ACTUAL_HOME/tools/exploit/sliver"
    
    if user_cmd_exists sliver-server || [[ -d "$sliver_target/.git" ]]; then
        log_success "Sliver already appears to be installed or cloned"
        ((SKIPPED_COUNT++))
        elif exec_cmd "Installing Sliver via official script" 2 "curl -fsSL https://sliver.sh/install | runuser -u $user_q -- env HOME=$home_q bash"; then
        log_success "Sliver installed via official script"
    else
        log_warning "Sliver official installer failed; cloning repository fallback"
        clone_or_update_repo "Cloning Sliver fallback" "https://github.com/BishopFox/sliver.git" "$sliver_target" 1
    fi
    
    install_pipx_tool "Installing impacket" impacket-GetNPUsers impacket
    apt_install_packages "Installing Metasploit Framework" metasploit-framework
    
    log_success "Exploitation tools installed"
}

################################################################################
# ACTIVE DIRECTORY TOOLS
################################################################################
install_ad_tools() {
    section_header "Installing Active Directory Tools"
    
    apt_install_packages "Installing Neo4j" neo4j
    run_cmd "Enabling Neo4j service" "warning" 2 "systemctl enable neo4j"
    run_cmd "Starting Neo4j service" "warning" 2 "systemctl start neo4j"
    
    clone_or_update_repo "Cloning BloodHound" "https://github.com/SpecterOps/BloodHound.git" "$ACTUAL_HOME/tools/ad/BloodHound" 1
    install_cargo_tool "Installing RustHound" rusthound rusthound
    install_pipx_tool "Installing Certipy" certipy certipy-ad
    install_pipx_tool "Installing Coercer" Coercer "git+https://github.com/p0dalirius/Coercer.git"
    
    log_success "Active Directory tools installed"
}

################################################################################
# PRIVILEGE ESCALATION TOOLS
################################################################################
install_privesc_tools() {
    section_header "Installing Privilege Escalation Tools"
    
    clone_or_update_repo "Cloning PEASS-ng" "https://github.com/carlospolop/PEASS-ng" "$ACTUAL_HOME/tools/privesc/PEASS-ng" 1
    run_as_user_cmd "Making linpeas executable" "warning" 1 "chmod +x \"\$HOME/tools/privesc/PEASS-ng/linPEAS/linpeas.sh\" 2>/dev/null || true"
    
    clone_or_update_repo "Cloning linux-exploit-suggester" "https://github.com/The-Z-Labs/linux-exploit-suggester" "$ACTUAL_HOME/tools/privesc/linux-exploit-suggester" 1
    run_as_user_cmd "Making linux-exploit-suggester executable" "warning" 1 "chmod +x \"\$HOME/tools/privesc/linux-exploit-suggester/linux-exploit-suggester.sh\" 2>/dev/null || true"
    
    log_success "Privilege escalation tools installed"
}

################################################################################
# AUTOMATION TOOLS
################################################################################
install_automation_tools() {
    section_header "Installing Automation Frameworks"
    
    install_pipx_tool "Installing AutoRecon" autorecon "git+https://github.com/Tib3rius/AutoRecon.git"
    
    log_success "Automation tools installed"
}

################################################################################
# OSINT TOOLS
################################################################################
install_osint_tools() {
    section_header "Installing OSINT Tools"
    
    install_pipx_tool "Installing sherlock" sherlock sherlock-project
    install_pipx_tool "Installing holehe" holehe "git+https://github.com/megadose/holehe.git"
    install_pipx_tool "Installing h8mail" h8mail h8mail
    
    log_success "OSINT tools installed"
}

################################################################################
# CLOUD TOOLS
################################################################################
install_cloud_tools() {
    section_header "Installing Cloud & Container Security Tools"
    
    progress "Installing trivy"
    if root_cmd_exists trivy; then
        log_success "trivy already available"
        ((SKIPPED_COUNT++))
        elif exec_cmd "Installing trivy via APT" 1 "DEBIAN_FRONTEND=noninteractive apt-get install -y trivy"; then
        log_success "trivy installed via APT"
    else
        log_warning "trivy not available via APT; using official install script fallback"
        run_cmd "Installing trivy via official script" "error" 2 "curl -sfL https://raw.githubusercontent.com/aquasecurity/trivy/main/contrib/install.sh | sh -s -- -b /usr/local/bin"
    fi
    
    install_pipx_tool "Installing kube-hunter" kube-hunter kube-hunter
    install_go_tool "Installing CloudFox" cloudfox "github.com/BishopFox/cloudfox@latest"
    install_pipx_tool "Installing ScoutSuite" scout scoutsuite
    install_pipx_tool "Installing Prowler" prowler prowler
    
    log_success "Cloud tools installed"
}

################################################################################
# MISCELLANEOUS TOOLS
################################################################################
install_misc_tools() {
    section_header "Installing Miscellaneous Tools"
    
    install_pipx_tool "Installing Ciphey" ciphey ciphey
    install_pipx_tool "Installing haiti" haiti haiti-hash
    install_go_tool "Installing GitLeaks" gitleaks "github.com/gitleaks/gitleaks/v8@latest"
    
    if user_cmd_exists trufflehog; then
        mark_skipped "Installing TruffleHog"
    else
        progress "Installing TruffleHog"
        local truffle_cmd truffle_cmd_q
        truffle_cmd='export PATH="$HOME/.local/bin:$HOME/go/bin:$HOME/.cargo/bin:/usr/local/go/bin:$PATH"; python3 -m pipx install trufflehog || pipx install trufflehog'
        truffle_cmd_q="$(q "$truffle_cmd")"
        if exec_cmd "Installing TruffleHog via pipx" 1 "runuser -u $(q "$ACTUAL_USER") -- env HOME=$(q "$ACTUAL_HOME") bash -lc $truffle_cmd_q"; then
            log_success "TruffleHog installed via pipx"
        else
            log_warning "TruffleHog pipx install failed; trying Go fallback"
            install_go_tool "Installing TruffleHog via Go" trufflehog "github.com/trufflesecurity/trufflehog/v3@latest"
        fi
    fi
    
    log_success "Miscellaneous tools installed"
}

################################################################################
# POST-INSTALLATION CONFIGURATION
################################################################################
post_install_config() {
    section_header "Post-Installation Configuration"
    
    if user_cmd_exists nuclei; then
        run_as_user_cmd "Initializing nuclei templates" "warning" 2 "nuclei -update-templates"
    else
        record_issue "warning" "Initializing nuclei templates skipped because nuclei is missing" 127 "nuclei -update-templates"
    fi
    
    run_as_user_cmd "Creating subfinder config directory" "warning" 1 "mkdir -p \"\$HOME/.config/subfinder\""
    run_as_user_cmd "Creating amass config directory" "warning" 1 "mkdir -p \"\$HOME/.config/amass\""
    
    log_success "Post-installation configuration completed"
}

################################################################################
# DOCUMENTATION
################################################################################
create_documentation() {
    section_header "Creating Documentation"
    progress "Creating tools README"
    
    if [[ "$DRY_RUN" == "1" ]]; then
        log_info "DRY_RUN: would write $ACTUAL_HOME/tools/README.md"
        return 0
    fi
    
    mkdir -p "$ACTUAL_HOME/tools"
    if cat > "$ACTUAL_HOME/tools/README.md" <<'EOFREADME'
# Tools Directory

## Structure
- **web/** - Web application security tools
- **recon/** - Reconnaissance and enumeration
- **network/** - Network analysis and pivoting
- **exploit/** - Exploitation frameworks and C2
- **ad/** - Active Directory tools
- **privesc/** - Privilege escalation tools
- **automation/** - Automation frameworks
- **osint/** - OSINT and information gathering
- **cloud/** - Cloud and container security
- **misc/** - Miscellaneous tools

## Tool Locations

### Command-Line Tools
- **Go tools** -> `~/go/bin/`: ffuf, httpx, katana, nuclei, dalfox, subfinder, assetfinder, amass, puredns, dnsx, naabu, chisel, ligolo-ng proxy/agent, cloudfox, gitleaks, trufflehog fallback
- **Rust tools** -> `~/.cargo/bin/`: feroxbuster, rustscan, rustcat, rusthound, eza fallback
- **Pipx tools** -> `~/.local/bin/`: impacket, certipy-ad, coercer, autorecon, sherlock, holehe, h8mail, ciphey, haiti, kube-hunter, arjun, scoutsuite, prowler
- **APT packages** -> `/usr/bin/`: sqlmap, neo4j, trivy, metasploit-framework, docker

### Repository Clones
- **~/tools/web/**: XSStrike, Corsy
- **~/tools/ad/**: BloodHound
- **~/tools/privesc/**: PEASS-ng, linux-exploit-suggester
- **~/tools/exploit/**: Sliver fallback clone if official installer failed

## Update Commands
- `update-tools` - Update all pentesting tools
- `update-wordlists` - Update wordlist repositories
- `update-system` - Update system packages

## Navigation Shortcuts
- `toolsweb`, `toolsrecon`, `toolsnetwork`, `toolsexploit`, `toolsad`, `toolsprivesc`, `toolsauto`, `toolsosint`, `toolscloud`, `toolsmisc`

## Tools Requiring API Keys
- **subfinder**: `~/.config/subfinder/provider-config.yaml`
- **amass**: `~/.config/amass/config.ini`

## BloodHound Setup
1. Start Neo4j: `sudo systemctl start neo4j`
2. Access Neo4j: `http://localhost:7474`
3. Default credentials: `neo4j/neo4j`; change on first login.
4. Launch or build BloodHound according to the repository instructions in `~/tools/ad/BloodHound`.
5. Collect data with RustHound: `rusthound [options]`.

## Soft-Fail Behavior
This setup script continues after individual failures. Review the terminal summary and `~/kali-setup.log` after each run. Re-running the script is safe for most steps: existing repositories are updated, existing tools are skipped, and failed package-manager states are repaired before retry.
EOFREADME
    then
        chown "$ACTUAL_USER:$ACTUAL_USER" "$ACTUAL_HOME/tools/README.md" 2>/dev/null || true
        log_success "Documentation created"
    else
        record_issue "error" "Creating tools README" 1 "$ACTUAL_HOME/tools/README.md"
    fi
}

################################################################################
# CLEANUP
################################################################################
cleanup() {
    section_header "System Cleanup"
    
    run_cmd "Running autoremove" "warning" 1 "DEBIAN_FRONTEND=noninteractive apt-get autoremove -y"
    run_cmd "Running autoclean" "warning" 1 "apt-get autoclean"
    
    log_success "Cleanup completed"
}

################################################################################
# VERIFICATION
################################################################################
verify_user_tool() {
    local tool="$1"
    if user_cmd_exists "$tool"; then
        log_success "$tool found in user PATH"
        return 0
    fi
    
    record_issue "warning" "$tool not found in user PATH" 127 "command -v $tool"
    return 0
}

verify_root_tool() {
    local tool="$1"
    if root_cmd_exists "$tool"; then
        log_success "$tool found in root PATH"
        return 0
    fi
    
    record_issue "warning" "$tool not found in root PATH" 127 "command -v $tool"
    return 0
}

verify_installation() {
    section_header "Verification Tests"
    
    progress "Testing Go tools"
    local go_tools=(httpx nuclei ffuf subfinder katana dalfox dnsx naabu chisel cloudfox gitleaks)
    local tool
    for tool in "${go_tools[@]}"; do
        verify_user_tool "$tool"
    done
    
    progress "Testing Rust tools"
    local rust_tools=(feroxbuster rustscan rustcat rusthound)
    for tool in "${rust_tools[@]}"; do
        verify_user_tool "$tool"
    done
    
    progress "Testing Python/pipx tools"
    local pipx_tools=(arjun certipy autorecon sherlock holehe h8mail ciphey haiti prowler)
    for tool in "${pipx_tools[@]}"; do
        verify_user_tool "$tool"
    done
    
    progress "Testing APT/root tools"
    local root_tools=(sqlmap docker neo4j)
    for tool in "${root_tools[@]}"; do
        verify_root_tool "$tool"
    done
    
    progress "Verifying Neo4j service"
    if systemctl is-active --quiet neo4j; then
        log_success "Neo4j service active"
    else
        record_issue "warning" "Neo4j service is not active" 1 "systemctl is-active neo4j"
    fi
    
    log_success "Verification completed"
}

################################################################################
# FINAL SUMMARY
################################################################################
display_summary() {
    local end_time elapsed minutes seconds
    end_time=$(date +%s)
    elapsed=$((end_time - SCRIPT_START_TIME))
    minutes=$((elapsed / 60))
    seconds=$((elapsed % 60))
    
    section_header "Installation Summary"
    
    echo -e "${GREEN}Installation workflow completed in ${minutes}m ${seconds}s${NC}"
    echo ""
    echo -e "${CYAN}Run statistics:${NC}"
    echo "  - Steps attempted: $CURRENT_STEP"
    echo "  - Soft errors: $ERROR_COUNT"
    echo "  - Warnings: $WARNING_COUNT"
    echo "  - Self-heal attempts: $SELF_HEAL_COUNT"
    echo "  - Skipped as already satisfied: $SKIPPED_COUNT"
    echo "  - Log file: $LOG_FILE"
    echo ""
    
    if [[ ${#FAILED_ACTIONS[@]} -gt 0 ]]; then
        echo -e "${RED}${BOLD}Soft errors requiring review:${NC}"
        local item
        for item in "${FAILED_ACTIONS[@]}"; do
            echo "  - $item"
        done
        echo ""
    fi
    
    if [[ ${#WARNING_ACTIONS[@]} -gt 0 ]]; then
        echo -e "${YELLOW}${BOLD}Warnings:${NC}"
        local item
        for item in "${WARNING_ACTIONS[@]}"; do
            echo "  - $item"
        done
        echo ""
    fi
    
    echo -e "${BOLD}${MAGENTA}MANUAL STEPS REQUIRED:${NC}"
    echo ""
    echo -e "${YELLOW}1. Log out and log back in for:${NC}"
    echo "   - Shell change to zsh"
    echo "   - Docker group membership activation"
    echo "   - PATH changes from pipx, Go and Cargo"
    echo ""
    echo -e "${YELLOW}2. Configure API keys for:${NC}"
    echo "   - subfinder: ~/.config/subfinder/provider-config.yaml"
    echo "   - amass: ~/.config/amass/config.ini"
    echo ""
    echo -e "${YELLOW}3. Setup Neo4j for BloodHound:${NC}"
    echo "   - sudo systemctl start neo4j"
    echo "   - Visit http://localhost:7474"
    echo "   - Change default password neo4j/neo4j"
    echo ""
    echo -e "${YELLOW}4. Build required tools when needed:${NC}"
    echo "   - BloodHound: cd ~/tools/ad/BloodHound && npm install && npm run build"
    echo "   - Sliver fallback: cd ~/tools/exploit/sliver && make"
    echo ""
    echo -e "${YELLOW}5. Smoke test after a new login shell:${NC}"
    echo "   - httpx -version"
    echo "   - nuclei -version"
    echo "   - toolsweb"
    echo ""
    
    if [[ $ERROR_COUNT -eq 0 ]]; then
        echo -e "${GREEN}Setup completed with no soft errors.${NC}"
    else
        echo -e "${YELLOW}Setup completed with soft errors. Review the summary and rerun after correcting blockers.${NC}"
    fi
}

################################################################################
# MAIN EXECUTION
################################################################################
main() {
    clear 2>/dev/null || true
    echo -e "${BOLD}${MAGENTA}"
    cat <<'EOFBANNER'
    ╔═══════════════════════════════════════════════════════════════╗
    ║                                                               ║
    ║        Kali Linux Complete Setup Script                       ║
    ║        Soft-Fail / Self-Healing Refactor                      ║
    ║        Version: 3.0                                           ║
    ║                                                               ║
    ╚═══════════════════════════════════════════════════════════════╝
EOFBANNER
    echo -e "${NC}"
    
    check_privileges "$@"
    parse_arguments "$@"
    log "Starting Kali Linux setup at $(date)"
    
    if [[ "$SOFT_ABORT" == "1" ]]; then
        display_summary
        return 0
    fi
    
    install_certificate
    update_system
    install_shell
    install_dev_tools
    configure_shell
    create_directory_structure
    clone_wordlists
    install_web_tools
    install_recon_tools
    install_network_tools
    install_exploit_tools
    install_ad_tools
    install_privesc_tools
    install_automation_tools
    install_osint_tools
    install_cloud_tools
    install_misc_tools
    post_install_config
    create_documentation
    cleanup
    verify_installation
    display_summary
    
    log "Setup completed at $(date)"
}

main "$@"

# Always return success to callers because failures are intentionally soft-reported.
exit 0
