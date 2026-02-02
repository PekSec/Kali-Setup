#!/usr/bin/env bash

################################################################################
# Kali Linux Complete Setup Script
# Author: Barış PEKALP
# Description: Automated setup for pentesting environment
# Usage: sudo ./kali-setup.sh [path/to/cert.crt]
################################################################################

# Removed set -e to allow proper error handling with || log_error patterns
# Error tracking is handled through ERROR_COUNT variable and trap handler

################################################################################
# COLOR CODES
################################################################################
readonly RED='\033[0;31m'
readonly GREEN='\033[0;32m'
readonly YELLOW='\033[1;33m'
readonly BLUE='\033[0;34m'
readonly MAGENTA='\033[0;35m'
readonly CYAN='\033[0;36m'
readonly NC='\033[0m' # No Color
readonly BOLD='\033[1m'

################################################################################
# GLOBAL VARIABLES
################################################################################
SCRIPT_START_TIME=$(date +%s)
LOG_FILE="$HOME/kali-setup.log"
ERROR_COUNT=0
CURRENT_STEP=0
TOTAL_STEPS=97  # Updated to match actual progress() calls (added 2 wordlist + 6 new tools + 4 Docker steps)
CERT_FILE=""

################################################################################
# LOGGING FUNCTIONS
################################################################################
log() {
    local message="$1"
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
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $1" | tee -a "$LOG_FILE"
    ((ERROR_COUNT++))
}

progress() {
    ((CURRENT_STEP++))
    echo -e "${CYAN}[${CURRENT_STEP}/${TOTAL_STEPS}]${NC} $1"
}

section_header() {
    echo ""
    echo -e "${BOLD}${MAGENTA}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo -e "${BOLD}${MAGENTA} $1${NC}"
    echo -e "${BOLD}${MAGENTA}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo ""
}

################################################################################
# ERROR HANDLING
################################################################################
handle_error() {
    local exit_code=$?
    local line_number=$1
    log_error "Command failed with exit code $exit_code at line $line_number"
    return 0  # Continue execution
}

trap 'handle_error ${LINENO}' ERR

################################################################################
# COMMAND VERIFICATION
################################################################################
check_command() {
    local cmd="$1"
    local install_msg="$2"

    if ! command -v "$cmd" &>/dev/null; then
        log_error "$cmd not found. $install_msg"
        return 1
    fi
    return 0
}

################################################################################
# PRIVILEGE CHECK
################################################################################
check_privileges() {
    section_header "Checking Privileges"
    
    if [[ $EUID -ne 0 ]]; then
        log_error "This script must be run as root or with sudo"
        exit 1
    fi
    
    # Get the actual user (not root)
    if [[ -n "$SUDO_USER" ]]; then
        ACTUAL_USER="$SUDO_USER"
        ACTUAL_HOME=$(eval echo ~$SUDO_USER)
    else
        ACTUAL_USER=$(whoami)
        ACTUAL_HOME="$HOME"
    fi
    
    log_success "Running as root with actual user: $ACTUAL_USER"
    log_info "User home directory: $ACTUAL_HOME"
}

################################################################################
# ARGUMENT PARSING
################################################################################
parse_arguments() {
    if [[ $# -gt 0 ]]; then
        CERT_FILE="$1"
        log_info "Certificate file provided: $CERT_FILE"
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
        log_error "Certificate file not found: $CERT_FILE"
        return 1
    fi
    
    progress "Installing custom certificate"
    
    local cert_name=$(basename "$CERT_FILE")
    cp "$CERT_FILE" "/usr/local/share/ca-certificates/$cert_name" || {
        log_error "Failed to copy certificate"
        return 1
    }
    
    update-ca-certificates || {
        log_error "Failed to update CA certificates"
        return 1
    }
    
    log_success "Certificate installed successfully"
}

################################################################################
# SYSTEM UPDATE
################################################################################
update_system() {
    section_header "System Update & Basic Packages"
    
    progress "Updating package lists"
    apt update || log_error "Failed to update package lists"
    
    progress "Upgrading system packages"
    apt upgrade -y || log_error "Failed to upgrade packages"
    
    progress "Installing basic tools"
    apt install -y git wget curl vim || log_error "Failed to install basic tools"
    
    progress "Installing modern CLI tools"
    apt install -y bat fd-find ripgrep tmux btop || log_error "Failed to install CLI tools"
    
    progress "Installing OpenJDK"
    apt install -y openjdk-21-jdk || apt install -y openjdk-17-jdk || log_error "Failed to install OpenJDK"

    progress "Installing build tools"
    apt install -y build-essential make || log_error "Failed to install build tools"

    progress "Installing Node.js for BloodHound"
    curl -fsSL https://deb.nodesource.com/setup_20.x | bash - || log_error "Failed to add Node.js repository"
    apt install -y nodejs || log_error "Failed to install Node.js"

    log_success "System update completed"
}

################################################################################
# SHELL INSTALLATION
################################################################################
install_shell() {
    section_header "Shell Installation"
    
    progress "Installing fish shell"
    apt install -y fish || log_error "Failed to install fish"
    
    progress "Installing Starship prompt"
    curl -sS https://starship.rs/install.sh | sh -s -- -y || log_error "Failed to install Starship"
    
    log_success "Shell tools installed"
}

################################################################################
# DEVELOPMENT TOOLS
################################################################################
install_dev_tools() {
    section_header "Development Tools Installation"
    
    # Python
    progress "Installing Python development tools"
    apt install -y python3-full python3-pip python3-venv || log_error "Failed to install Python tools"
    
    progress "Installing pipx"
    apt install -y pipx || log_error "Failed to install pipx"
    su - "$ACTUAL_USER" -c "pipx ensurepath" || log_warning "pipx ensurepath failed"
    
    # Docker - Official Docker CE Installation
    progress "Removing old Docker packages"
    apt remove -y docker.io docker-compose docker-doc podman-docker containerd runc 2>/dev/null || log_info "Old Docker packages not installed or already removed"
    
    progress "Installing Docker prerequisites"
    apt install -y ca-certificates curl || log_error "Failed to install Docker prerequisites"
    
    progress "Setting up Docker GPG key"
    install -m 0755 -d /etc/apt/keyrings || log_error "Failed to create keyrings directory"
    curl -fsSL https://download.docker.com/linux/debian/gpg -o /etc/apt/keyrings/docker.asc || log_error "Failed to download Docker GPG key"
    chmod a+r /etc/apt/keyrings/docker.asc || log_error "Failed to set permissions on Docker GPG key"
    
    progress "Adding Docker repository for Debian 13 Trixie"
    tee /etc/apt/sources.list.d/docker.sources > /dev/null <<EOF
Types: deb
URIs: https://download.docker.com/linux/debian
Suites: trixie
Components: stable
Signed-By: /etc/apt/keyrings/docker.asc
EOF
    
    progress "Updating package lists for Docker repository"
    apt update || log_error "Failed to update package lists after adding Docker repository"
    
    progress "Installing Docker CE and plugins"
    apt install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin || log_error "Failed to install Docker CE"
    
    progress "Adding user to docker group"
    usermod -aG docker "$ACTUAL_USER" || log_error "Failed to add user to docker group"
    
    # Go
    progress "Installing Go"
    apt install -y golang-go || log_error "Failed to install Go"
    
    # Rust
    progress "Installing Rust for user"
    su - "$ACTUAL_USER" -c 'curl --proto "=https" --tlsv1.2 -sSf https://sh.rustup.rs | sh -s -- -y' || log_error "Failed to install Rust for user"
    
    progress "Installing Rust for root"
    curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | sh -s -- -y || log_error "Failed to install Rust for root"

    # Source Rust environment with verification
    progress "Verifying Rust environment"
    if ! source "$ACTUAL_HOME/.cargo/env" 2>/dev/null; then
        log_warning "Failed to source user Rust environment at $ACTUAL_HOME/.cargo/env"
    fi

    if ! source /root/.cargo/env 2>/dev/null; then
        log_warning "Failed to source root Rust environment"
    fi

    # Verify cargo is available
    if ! command -v cargo &>/dev/null; then
        log_error "Cargo not found in PATH after Rust installation"
    else
        log_success "Rust and Cargo successfully configured"
    fi

    # Install eza now that Rust/cargo is available
    progress "Installing eza (modern ls)"
    apt install -y eza || {
        log_warning "eza not in repos, installing via cargo"
        su - "$ACTUAL_USER" -c "source ~/.cargo/env && cargo install eza" || log_error "Failed to install eza"
    }

    log_success "Development tools installed"
}

################################################################################
# SHELL CONFIGURATION
################################################################################
configure_shell() {
    section_header "Shell Configuration"
    
    progress "Changing user shell to fish"
    chsh -s /usr/bin/fish "$ACTUAL_USER" || log_error "Failed to change user shell"
    
    progress "Changing root shell to fish"
    chsh -s /usr/bin/fish root || log_error "Failed to change root shell"
    
    progress "Setting up Starship for user"
    mkdir -p "$ACTUAL_HOME/.config"
    chown "$ACTUAL_USER":"$ACTUAL_USER" "$ACTUAL_HOME/.config"
    su - "$ACTUAL_USER" -c "starship preset nerd-font-symbols -o ~/.config/starship.toml" || log_error "Failed to setup user Starship"
    
    progress "Setting up Starship for root"
    mkdir -p /root/.config
    starship preset nerd-font-symbols -o /root/.config/starship.toml || log_error "Failed to setup root Starship"
    
    log_success "Shell configuration completed"
}

################################################################################
# FISH GLOBAL CONFIGURATION
################################################################################
configure_fish_global() {
    section_header "Fish Global Configuration"
    
    progress "Creating global fish config"
    
    cat > /etc/fish/config.fish << 'EOF'
# Starship initialization (with availability check)
if command -v starship >/dev/null 2>&1
    starship init fish | source
else
    echo "Warning: Starship not found - install with: curl -sS https://starship.rs/install.sh | sh"
end

# Disable fish greeting
set -g fish_greeting

# Eza aliases (with availability check)
if command -v eza >/dev/null 2>&1
    alias ls='eza --icons --group-directories-first'
    alias tree='eza --tree --icons'
else
    # Fallback to standard ls
    alias ls='ls --color=auto'
end

# Fish abbreviations
if command -v eza >/dev/null 2>&1
    abbr -a ll 'eza -la --icons --group-directories-first'
    abbr -a la 'eza -a --icons --group-directories-first'
else
    abbr -a ll 'ls -la'
    abbr -a la 'ls -a'
end
abbr -a .. 'cd ..'
abbr -a ... 'cd ../..'
abbr -a .... 'cd ../../..'

# Git abbreviations
abbr -a gst 'git status'
abbr -a gco 'git checkout'
abbr -a gp 'git pull'
abbr -a gps 'git push'
abbr -a ga 'git add'
abbr -a gc 'git commit'
abbr -a gd 'git diff'
abbr -a gl 'git log --oneline --graph'

# Docker abbreviations
abbr -a dps 'docker ps'
abbr -a dpsa 'docker ps -a'
abbr -a di 'docker images'
abbr -a dex 'docker exec -it'
abbr -a dlog 'docker logs -f'

# Add Go binaries to PATH
set -gx PATH $PATH /usr/local/go/bin
set -gx PATH $PATH $HOME/go/bin

# Add Cargo binaries to PATH
set -gx PATH $PATH $HOME/.cargo/bin

# Add local bin to PATH
set -gx PATH $PATH $HOME/.local/bin

# Set GOPATH
set -gx GOPATH $HOME/go

# System update function
function update-system
    echo "Updating system..."
    sudo apt update
    sudo apt upgrade -y
    sudo apt autoremove -y
    sudo apt autoclean
    echo "System update complete!"
end

# Wordlist update function
function update-wordlists
    echo "Updating wordlists..."
    set wordlist_dirs ~/wordlists/fuzzdb ~/wordlists/SecLists ~/wordlists/PayloadsAllTheThings ~/wordlists/Default-Accounts-Arsenal
    for dir in $wordlist_dirs
        if test -d $dir
            echo "Updating $dir"
            git -C $dir pull
        end
    end
    echo "Wordlists updated!"
end

# Tools update function
function update-tools
    echo "Updating pentesting tools..."

    # Update Go tools
    echo "Updating Go tools..."
    go install github.com/ffuf/ffuf/v2@latest
    go install github.com/projectdiscovery/httpx/cmd/httpx@latest
    go install github.com/projectdiscovery/subfinder/v2/cmd/subfinder@latest
    go install github.com/projectdiscovery/nuclei/v3/cmd/nuclei@latest
    go install github.com/projectdiscovery/katana/cmd/katana@latest
    go install github.com/projectdiscovery/naabu/v2/cmd/naabu@latest
    go install github.com/projectdiscovery/dnsx/cmd/dnsx@latest
    go install github.com/hahwul/dalfox/v2@latest
    go install github.com/tomnomnom/assetfinder@latest
    go install github.com/d3mondev/puredns/v2@latest
    go install github.com/owasp-amass/amass/v4/...@master
    go install github.com/jpillora/chisel@latest
    go install github.com/nicocha30/ligolo-ng/cmd/proxy@latest
    go install github.com/nicocha30/ligolo-ng/cmd/agent@latest
    go install github.com/BishopFox/cloudfox@latest
    go install github.com/gitleaks/gitleaks/v8@latest

    # Update Rust tools
    echo "Updating Rust tools..."
    cargo install feroxbuster --force
    cargo install rustscan --force
    cargo install rustcat --force
    cargo install rusthound --force
    cargo install eza --force

    # Update pipx tools
    echo "Updating pipx tools..."
    pipx upgrade-all

    # Update nuclei templates
    echo "Updating nuclei templates..."
    nuclei -update-templates

    # Update APT tools
    echo "Updating system packages..."
    sudo apt update && sudo apt upgrade -y

    echo "Tools update complete!"
end

# Python venv activation helper
function venv
    if test -d ./venv
        source ./venv/bin/activate.fish
    else if test -d ./.venv
        source ./.venv/bin/activate.fish
    else
        echo "No virtual environment found in current directory"
    end
end

# Tools navigation functions
function toolsweb; cd ~/tools/web; end
function toolsrecon; cd ~/tools/recon; end
function toolsnetwork; cd ~/tools/network; end
function toolsexploit; cd ~/tools/exploit; end
function toolsad; cd ~/tools/ad; end
function toolsprivesc; cd ~/tools/privesc; end
function toolsauto; cd ~/tools/automation; end
function toolsosint; cd ~/tools/osint; end
function toolscloud; cd ~/tools/cloud; end
function toolsmisc; cd ~/tools/misc; end
EOF

    log_success "Fish global configuration created"
}

################################################################################
# DIRECTORY STRUCTURE
################################################################################
create_directory_structure() {
    section_header "Creating Directory Structure"
    
    progress "Creating pentesting directories"
    su - "$ACTUAL_USER" -c "mkdir -p ~/wordlists ~/pentests ~/tools/{web,recon,network,exploit,ad,privesc,automation,osint,cloud,misc}"
    
    progress "Creating monthly pentest directories"
    su - "$ACTUAL_USER" -c "mkdir -p ~/pentests/2026.{01..12}"
    
    progress "Setting proper permissions"
    find "$ACTUAL_HOME/tools" -type d -exec chmod 755 {} \; 2>/dev/null || true
    find "$ACTUAL_HOME/wordlists" -type d -exec chmod 755 {} \; 2>/dev/null || true
    find "$ACTUAL_HOME/pentests" -type d -exec chmod 755 {} \; 2>/dev/null || true
    
    log_success "Directory structure created"
}

################################################################################
# WORDLIST REPOSITORIES
################################################################################
clone_wordlists() {
    section_header "Cloning Wordlist Repositories"

    progress "Removing seclists package (if installed)"
    apt remove -y seclists 2>/dev/null || log_info "seclists package not installed or already removed"

    progress "Cloning fuzzdb"
    su - "$ACTUAL_USER" -c "git clone --depth 1 https://github.com/fuzzdb-project/fuzzdb.git ~/wordlists/fuzzdb" || log_error "Failed to clone fuzzdb"

    progress "Cloning SecLists"
    su - "$ACTUAL_USER" -c "git clone --depth 1 https://github.com/danielmiessler/SecLists.git ~/wordlists/SecLists" || log_error "Failed to clone SecLists"

    progress "Cloning PayloadsAllTheThings"
    su - "$ACTUAL_USER" -c "git clone --depth 1 https://github.com/swisskyrepo/PayloadsAllTheThings.git ~/wordlists/PayloadsAllTheThings" || log_error "Failed to clone PayloadsAllTheThings"

    progress "Cloning Default-Accounts-Arsenal"
    su - "$ACTUAL_USER" -c "git clone --depth 1 https://github.com/PekSec/Default-Accounts-Arsenal.git ~/wordlists/Default-Accounts-Arsenal" || log_error "Failed to clone Default-Accounts-Arsenal"
    
    log_success "Wordlist repositories cloned"
}

################################################################################
# WEB TOOLS
################################################################################
install_web_tools() {
    section_header "Installing Web Application Security Tools"
    
    # Go-based tools
    progress "Installing ffuf"
    su - "$ACTUAL_USER" -c "go install github.com/ffuf/ffuf/v2@latest" || log_error "Failed to install ffuf"
    
    progress "Installing httpx"
    su - "$ACTUAL_USER" -c "go install github.com/projectdiscovery/httpx/cmd/httpx@latest" || log_error "Failed to install httpx"
    
    progress "Installing katana"
    su - "$ACTUAL_USER" -c "go install github.com/projectdiscovery/katana/cmd/katana@latest" || log_error "Failed to install katana"
    
    progress "Installing nuclei"
    su - "$ACTUAL_USER" -c "go install github.com/projectdiscovery/nuclei/v3/cmd/nuclei@latest" || log_error "Failed to install nuclei"
    
    progress "Installing dalfox"
    su - "$ACTUAL_USER" -c "go install github.com/hahwul/dalfox/v2@latest" || log_error "Failed to install dalfox"
    
    # Rust-based tools
    progress "Installing feroxbuster"
    su - "$ACTUAL_USER" -c "source ~/.cargo/env && cargo install feroxbuster" || log_error "Failed to install feroxbuster"

    # Python tools via pipx (isolated environments)
    progress "Installing XSStrike with dependencies"
    su - "$ACTUAL_USER" -c "git clone --depth 1 https://github.com/s0md3v/XSStrike.git ~/tools/web/XSStrike && \
        cd ~/tools/web/XSStrike && \
        python3 -m pip install --user -r requirements.txt" || log_error "Failed to install XSStrike"

    progress "Installing Arjun"
    su - "$ACTUAL_USER" -c "pipx install arjun" || log_error "Failed to install Arjun"

    progress "Installing Corsy with dependencies"
    su - "$ACTUAL_USER" -c "git clone --depth 1 https://github.com/s0md3v/Corsy.git ~/tools/web/Corsy && \
        cd ~/tools/web/Corsy && \
        python3 -m pip install --user -r requirements.txt" || log_error "Failed to install Corsy"

    progress "Installing sqlmap"
    apt install -y sqlmap || log_error "Failed to install sqlmap"
    
    log_success "Web tools installed"
}

################################################################################
# RECON TOOLS
################################################################################
install_recon_tools() {
    section_header "Installing Reconnaissance & Enumeration Tools"
    
    progress "Installing subfinder"
    su - "$ACTUAL_USER" -c "go install github.com/projectdiscovery/subfinder/v2/cmd/subfinder@latest" || log_error "Failed to install subfinder"
    
    progress "Installing assetfinder"
    su - "$ACTUAL_USER" -c "go install github.com/tomnomnom/assetfinder@latest" || log_error "Failed to install assetfinder"
    
    progress "Installing amass"
    su - "$ACTUAL_USER" -c "go install github.com/owasp-amass/amass/v4/...@master" || log_error "Failed to install amass"
    
    progress "Installing puredns"
    su - "$ACTUAL_USER" -c "go install github.com/d3mondev/puredns/v2@latest" || log_error "Failed to install puredns"
    
    progress "Installing dnsx"
    su - "$ACTUAL_USER" -c "go install github.com/projectdiscovery/dnsx/cmd/dnsx@latest" || log_error "Failed to install dnsx"
    
    progress "Installing naabu"
    su - "$ACTUAL_USER" -c "go install github.com/projectdiscovery/naabu/v2/cmd/naabu@latest" || log_error "Failed to install naabu"
    
    progress "Installing rustscan"
    su - "$ACTUAL_USER" -c "source ~/.cargo/env && cargo install rustscan" || log_error "Failed to install rustscan"
    
    log_success "Recon tools installed"
}

################################################################################
# NETWORK TOOLS
################################################################################
install_network_tools() {
    section_header "Installing Network Analysis & Pivoting Tools"
    
    progress "Installing chisel"
    su - "$ACTUAL_USER" -c "go install github.com/jpillora/chisel@latest" || log_error "Failed to install chisel"
    
    progress "Installing ligolo-ng proxy"
    su - "$ACTUAL_USER" -c "go install github.com/nicocha30/ligolo-ng/cmd/proxy@latest" || log_error "Failed to install ligolo-ng proxy"
    
    progress "Installing ligolo-ng agent"
    su - "$ACTUAL_USER" -c "go install github.com/nicocha30/ligolo-ng/cmd/agent@latest" || log_error "Failed to install ligolo-ng agent"
    
    progress "Installing rustcat"
    su - "$ACTUAL_USER" -c "source ~/.cargo/env && cargo install rustcat" || log_error "Failed to install rustcat"
    
    log_success "Network tools installed"
}

################################################################################
# EXPLOITATION TOOLS
################################################################################
install_exploit_tools() {
    section_header "Installing Exploitation & C2 Frameworks"

    progress "Installing Sliver C2 Framework"
    curl https://sliver.sh/install | su - "$ACTUAL_USER" -c "bash" || {
        log_warning "Failed to install via script, cloning repository"
        su - "$ACTUAL_USER" -c "git clone https://github.com/BishopFox/sliver.git ~/tools/exploit/sliver" || log_error "Failed to clone sliver"
    }

    progress "Installing impacket"
    su - "$ACTUAL_USER" -c "pipx install impacket" || log_error "Failed to install impacket"

    progress "Installing Metasploit Framework"
    apt install -y metasploit-framework || log_error "Failed to install Metasploit Framework"

    log_success "Exploitation tools installed"
}

################################################################################
# ACTIVE DIRECTORY TOOLS
################################################################################
install_ad_tools() {
    section_header "Installing Active Directory Tools"
    
    progress "Installing Neo4j"
    apt install -y neo4j || log_error "Failed to install Neo4j"

    progress "Enabling Neo4j service"
    systemctl enable neo4j &>/dev/null || log_warning "Failed to enable Neo4j service"

    progress "Starting Neo4j service"
    systemctl start neo4j &>/dev/null || log_warning "Failed to start Neo4j - start manually with: sudo systemctl start neo4j"

    progress "Cloning BloodHound"
    su - "$ACTUAL_USER" -c "git clone --depth 1 https://github.com/SpecterOps/BloodHound.git ~/tools/ad/BloodHound" || log_error "Failed to clone BloodHound"
    
    progress "Installing RustHound"
    su - "$ACTUAL_USER" -c "source ~/.cargo/env && cargo install rusthound" || log_error "Failed to install RustHound"
    
    progress "Installing Certipy"
    su - "$ACTUAL_USER" -c "pipx install certipy-ad" || log_error "Failed to install Certipy"

    progress "Installing Coercer"
    su - "$ACTUAL_USER" -c "pipx install git+https://github.com/p0dalirius/Coercer.git" || log_error "Failed to install Coercer"
    
    log_success "Active Directory tools installed"
}

################################################################################
# PRIVILEGE ESCALATION TOOLS
################################################################################
install_privesc_tools() {
    section_header "Installing Privilege Escalation Tools"

    progress "Cloning PEASS-ng"
    su - "$ACTUAL_USER" -c "git clone --depth 1 https://github.com/carlospolop/PEASS-ng ~/tools/privesc/PEASS-ng && chmod +x ~/tools/privesc/PEASS-ng/linPEAS/linpeas.sh" || log_error "Failed to clone PEASS-ng"

    progress "Cloning linux-exploit-suggester"
    su - "$ACTUAL_USER" -c "git clone --depth 1 https://github.com/The-Z-Labs/linux-exploit-suggester ~/tools/privesc/linux-exploit-suggester && chmod +x ~/tools/privesc/linux-exploit-suggester/linux-exploit-suggester.sh" || log_error "Failed to clone linux-exploit-suggester"
    
    log_success "Privilege escalation tools installed"
}

################################################################################
# AUTOMATION TOOLS
################################################################################
install_automation_tools() {
    section_header "Installing Automation Frameworks"

    progress "Installing AutoRecon"
    su - "$ACTUAL_USER" -c "pipx install git+https://github.com/Tib3rius/AutoRecon.git" || log_error "Failed to install AutoRecon"

    log_success "Automation tools installed"
}

################################################################################
# OSINT TOOLS
################################################################################
install_osint_tools() {
    section_header "Installing OSINT Tools"
    
    progress "Installing sherlock"
    su - "$ACTUAL_USER" -c "pipx install sherlock-project" || log_error "Failed to install sherlock"

    progress "Installing holehe"
    su - "$ACTUAL_USER" -c "pipx install git+https://github.com/megadose/holehe.git" || log_error "Failed to install holehe"

    progress "Installing h8mail"
    su - "$ACTUAL_USER" -c "pipx install h8mail" || log_error "Failed to install h8mail"
    
    log_success "OSINT tools installed"
}

################################################################################
# CLOUD TOOLS
################################################################################
install_cloud_tools() {
    section_header "Installing Cloud & Container Security Tools"

    progress "Installing trivy"
    apt install -y trivy || {
        log_warning "trivy not in repos, installing from official script"
        curl -sfL https://raw.githubusercontent.com/aquasecurity/trivy/main/contrib/install.sh | sh -s -- -b /usr/local/bin || log_error "Failed to install trivy"
    }

    progress "Installing kube-hunter"
    su - "$ACTUAL_USER" -c "pipx install kube-hunter" || log_error "Failed to install kube-hunter"

    progress "Installing CloudFox"
    su - "$ACTUAL_USER" -c "go install github.com/BishopFox/cloudfox@latest" || log_error "Failed to install CloudFox"

    progress "Installing ScoutSuite"
    su - "$ACTUAL_USER" -c "pipx install scoutsuite" || log_error "Failed to install ScoutSuite"

    progress "Installing Prowler"
    su - "$ACTUAL_USER" -c "pipx install prowler" || log_error "Failed to install Prowler"

    log_success "Cloud tools installed"
}

################################################################################
# MISCELLANEOUS TOOLS
################################################################################
install_misc_tools() {
    section_header "Installing Miscellaneous Tools"
    
    progress "Installing Ciphey"
    su - "$ACTUAL_USER" -c "pipx install ciphey" || log_error "Failed to install Ciphey"
    
    progress "Installing haiti"
    su - "$ACTUAL_USER" -c "pipx install haiti-hash" || log_error "Failed to install haiti"

    progress "Installing GitLeaks"
    su - "$ACTUAL_USER" -c "go install github.com/gitleaks/gitleaks/v8@latest" || log_error "Failed to install GitLeaks"

    progress "Installing TruffleHog"
    su - "$ACTUAL_USER" -c "pipx install trufflehog" || log_error "Failed to install TruffleHog"
    
    log_success "Miscellaneous tools installed"
}

################################################################################
# POST-INSTALLATION CONFIGURATION
################################################################################
post_install_config() {
    section_header "Post-Installation Configuration"
    
    progress "Initializing nuclei templates"
    su - "$ACTUAL_USER" -c "nuclei -update-templates" || log_warning "Failed to update nuclei templates"
    
    progress "Creating subfinder config directory"
    su - "$ACTUAL_USER" -c "mkdir -p ~/.config/subfinder" || log_warning "Failed to create subfinder config"
    
    progress "Creating amass config directory"
    su - "$ACTUAL_USER" -c "mkdir -p ~/.config/amass" || log_warning "Failed to create amass config"
    
    log_success "Post-installation configuration completed"
}

################################################################################
# DOCUMENTATION
################################################################################
create_documentation() {
    section_header "Creating Documentation"
    
    progress "Creating tools README"
    
    cat > "$ACTUAL_HOME/tools/README.md" << 'EOFREADME'
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

### Command-Line Tools (automatically in PATH)
- **Go tools** → `~/go/bin/`: ffuf, httpx, katana, nuclei, dalfox, subfinder, assetfinder, amass, puredns, dnsx, naabu, chisel, ligolo-ng (proxy+agent)
- **Rust tools** → `~/.cargo/bin/`: feroxbuster, rustscan, rustcat, rusthound, eza
- **Pipx tools** → `~/.local/bin/`: impacket, certipy-ad, coercer, autorecon, sherlock, holehe, h8mail, ciphey, haiti, kube-hunter, arjun
- **APT packages** → `/usr/bin/`: sqlmap, neo4j, trivy

### Repository Clones (for manual execution or building)
- **~/tools/web/**: XSStrike, Corsy (with Python dependencies installed)
- **~/tools/ad/**: BloodHound (requires: cd ~/tools/ad/BloodHound && npm install && npm run build)
- **~/tools/privesc/**: PEASS-ng, linux-exploit-suggester
- **~/tools/exploit/**: sliver (if official installer failed, requires: cd ~/tools/exploit/sliver && make)

## Installed Tools Summary

### Web Tools (10)
- **Go**: ffuf, httpx, katana, nuclei, dalfox
- **Rust**: feroxbuster
- **Python**: XSStrike, Arjun, Corsy
- **APT**: sqlmap

### Recon Tools (7)
- subfinder, assetfinder, amass, puredns, dnsx, naabu, rustscan

### Network Tools (4)
- chisel, ligolo-ng (proxy+agent), rustcat

### Exploitation Tools (2)
- Sliver C2, impacket

### Active Directory Tools (5)
- Neo4j, BloodHound, RustHound, Certipy, Coercer

### Privilege Escalation (2)
- PEASS-ng, linux-exploit-suggester

### Automation (1)
- AutoRecon

### OSINT Tools (3)
- sherlock, holehe, h8mail

### Cloud Tools (2)
- trivy, kube-hunter

### Miscellaneous (2)
- Ciphey, haiti

## Update Commands
- `update-tools` - Update all pentesting tools
- `update-wordlists` - Update wordlist repositories
- `update-system` - Update system packages

## Navigation Shortcuts
- `toolsweb` - Navigate to ~/tools/web
- `toolsrecon` - Navigate to ~/tools/recon
- `toolsnetwork` - Navigate to ~/tools/network
- `toolsexploit` - Navigate to ~/tools/exploit
- `toolsad` - Navigate to ~/tools/ad
- `toolsprivesc` - Navigate to ~/tools/privesc
- `toolsauto` - Navigate to ~/tools/automation
- `toolsosint` - Navigate to ~/tools/osint
- `toolscloud` - Navigate to ~/tools/cloud
- `toolsmisc` - Navigate to ~/tools/misc

## Tools Requiring API Keys
- **subfinder**: ~/.config/subfinder/provider-config.yaml
- **amass**: ~/.config/amass/config.ini

## BloodHound Setup
1. Start Neo4j: `sudo systemctl start neo4j`
2. Access Neo4j: http://localhost:7474
3. Default credentials: neo4j/neo4j (change on first login)
4. Launch BloodHound: Check build instructions in ~/tools/ad/BloodHound
5. Collect data with RustHound: `rusthound [options]`

## Tools Notes

### Sliver C2 Framework
- **Installation**: Installed via official script (https://sliver.sh/install)
- **Fallback**: If script fails, cloned to ~/tools/exploit/sliver (requires `make`)

### BloodHound CE
- **Location**: ~/tools/ad/BloodHound
- **Note**: Requires manual build, check README.md in the repository

### XSStrike & Corsy
- **Locations**: ~/tools/web/XSStrike, ~/tools/web/Corsy
- **Usage**: Run directly with Python (dependencies via requirements.txt handled during clone)
EOFREADME

    chown "$ACTUAL_USER":"$ACTUAL_USER" "$ACTUAL_HOME/tools/README.md"
    log_success "Documentation created"
}

################################################################################
# CLEANUP
################################################################################
cleanup() {
    section_header "System Cleanup"
    
    progress "Running autoremove"
    apt autoremove -y || log_warning "Autoremove failed"
    
    progress "Running autoclean"
    apt autoclean || log_warning "Autoclean failed"
    
    log_success "Cleanup completed"
}

################################################################################
# VERIFICATION
################################################################################
verify_installation() {
    section_header "Verification Tests"

    local verification_errors=0

    progress "Testing Go tools"
    for tool in httpx nuclei ffuf subfinder; do
        if su - "$ACTUAL_USER" -c "command -v $tool" &>/dev/null; then
            log_success "$tool found in PATH"
        else
            log_error "$tool not found - installation may have failed"
            ((verification_errors++))
        fi
    done

    progress "Testing Rust tools"
    for tool in feroxbuster rustscan; do
        if su - "$ACTUAL_USER" -c "command -v $tool" &>/dev/null; then
            log_success "$tool found in PATH"
        else
            log_error "$tool not found - installation may have failed"
            ((verification_errors++))
        fi
    done

    progress "Testing Python tools"
    if su - "$ACTUAL_USER" -c "pipx list" &>/dev/null; then
        log_success "pipx tools installed"
    else
        log_error "pipx tools not found"
        ((verification_errors++))
    fi

    progress "Verifying Neo4j"
    if systemctl status neo4j &>/dev/null; then
        log_success "Neo4j service active"
    else
        log_warning "Neo4j not active (will be started manually)"
    fi

    if [[ $verification_errors -gt 0 ]]; then
        log_error "Verification completed with $verification_errors failures"
    else
        log_success "All critical tools verified successfully"
    fi
}

################################################################################
# FINAL SUMMARY
################################################################################
display_summary() {
    local end_time=$(date +%s)
    local elapsed=$((end_time - SCRIPT_START_TIME))
    local minutes=$((elapsed / 60))
    local seconds=$((elapsed % 60))
    
    section_header "Installation Summary"
    
    echo -e "${GREEN}Installation completed in ${minutes}m ${seconds}s${NC}"
    echo ""
    echo -e "${YELLOW}Errors encountered: $ERROR_COUNT${NC}"
    echo ""
    echo -e "${CYAN}Statistics:${NC}"
    echo "  - Total tools installed: 47"
    echo "  - Wordlist repositories: 4"
    echo "  - Directory categories: 10"
    echo "  - Go tools: 16 (+ cloudfox, gitleaks)"
    echo "  - Rust tools: 5 (feroxbuster, rustscan, rustcat, rusthound, eza)"
    echo "  - Pipx tools: 14 (+ scoutsuite, prowler, trufflehog)"
    echo "  - APT tools: 4 (sqlmap, neo4j, trivy, metasploit-framework)"
    echo "  - Git clone tools: 5 (XSStrike, Corsy, BloodHound, PEASS-ng, linux-exploit-suggester)"
    echo "  - Build dependencies: Node.js, build-essential, make"
    echo ""
    echo -e "${BOLD}${MAGENTA}MANUAL STEPS REQUIRED:${NC}"
    echo ""
    echo -e "${YELLOW}1. Log out and log back in for:${NC}"
    echo "   - Shell changes to take effect"
    echo "   - Docker group membership activation"
    echo "   - PATH changes to be applied"
    echo ""
    echo -e "${YELLOW}2. Configure API keys for:${NC}"
    echo "   - subfinder: ~/.config/subfinder/provider-config.yaml"
    echo "   - amass: ~/.config/amass/config.ini"
    echo ""
    echo -e "${YELLOW}3. Setup Neo4j for BloodHound:${NC}"
    echo "   - sudo systemctl start neo4j"
    echo "   - Visit http://localhost:7474"
    echo "   - Change default password (neo4j/neo4j)"
    echo ""
    echo -e "${YELLOW}4. Build required tools:${NC}"
    echo "   - BloodHound: cd ~/tools/ad/BloodHound && npm install && npm run build"
    echo "   - Sliver: Only if official installer failed: cd ~/tools/exploit/sliver && make"
    echo ""
    echo -e "${YELLOW}5. Test your setup:${NC}"
    echo "   - Open new terminal"
    echo "   - Run: httpx -version"
    echo "   - Run: nuclei -version"
    echo "   - Run: toolsweb (should navigate to ~/tools/web)"
    echo ""
    echo -e "${CYAN}Configuration Files:${NC}"
    echo "  - Fish config: /etc/fish/config.fish"
    echo "  - Starship (user): ~/.config/starship.toml"
    echo "  - Starship (root): /root/.config/starship.toml"
    echo "  - Tools README: ~/tools/README.md"
    echo "  - Log file: $LOG_FILE"
    echo ""
    echo -e "${GREEN}Setup completed successfully!${NC}"
}

################################################################################
# MAIN EXECUTION
################################################################################
main() {
    clear
    echo -e "${BOLD}${MAGENTA}"
    cat << 'EOF'
    ╔═══════════════════════════════════════════════════════════════╗
    ║                                                               ║
    ║        Kali Linux Complete Setup Script                       ║
    ║        Author: Barış PEKALP                                   ║
    ║        Version: 2.0                                           ║
    ║                                                               ║
    ╚═══════════════════════════════════════════════════════════════╝
EOF
    echo -e "${NC}"
    
    log "Starting Kali Linux setup at $(date)"
    
    # Execute all functions in order
    check_privileges
    parse_arguments "$@"
    install_certificate
    update_system
    install_shell
    install_dev_tools
    configure_shell
    configure_fish_global
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

# Run main function
main "$@"
