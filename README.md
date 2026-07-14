# 🛡️ Kali Linux Setup Script

Automated, **soft-fail / self-healing** setup for a Kali (Debian-based) penetration-testing
environment. One run installs ~45 offensive-security tools, a modern zsh shell, and an
organized workspace — without aborting the whole install when a single tool fails.

- **Author:** Barış PEKALP
- **Version:** 3.0 (soft-fail / self-healing refactor)
- **Repo:** https://github.com/PekSec/Kali-Setup

---

## 📋 Table of Contents

- [Design Philosophy](#-design-philosophy)
- [Prerequisites](#-prerequisites)
- [Quick Start](#-quick-start)
- [Configuration Flags](#-configuration-flags)
- [What Gets Installed](#-what-gets-installed)
- [Shell Environment (zsh)](#-shell-environment-zsh)
- [Directory Layout](#-directory-layout)
- [Post-Installation](#-post-installation)
- [Updating](#-updating)
- [Troubleshooting](#-troubleshooting)

---

## 🎯 Design Philosophy

This script is deliberately **soft-fail**: there is no `set -e`. Every individual tool or
package install is wrapped so a failure is logged and recorded, then the run continues. At the
end you get a structured summary of soft errors and warnings instead of a half-finished system.

Key properties:

- **No fail-fast** — one broken tool never blocks the other 40+.
- **Self-healing** — transient failures are retried; apt/dpkg lock waits, `dpkg --configure -a`,
  Go/Rust/pipx environment repairs, and `systemctl daemon-reload` are attempted automatically.
- **Idempotent** — safe to re-run. Installed tools are skipped, existing repos are `git pull`ed,
  and an existing `.zshrc` is backed up before replacement.
- **No system-package breakage** — Python tooling uses `pipx` (isolated venvs) or user-managed
  venvs. The script never runs `pip install --break-system-packages`.
- **Structured logging** — everything is timestamped to `~/kali-setup.log`, and a colored
  summary prints at the end.

---

## 🔧 Prerequisites

| Requirement | Detail |
|-------------|--------|
| **OS** | Kali Linux / Debian-based (Docker repo defaults to the `trixie` suite, falls back to `bookworm`) |
| **Privileges** | Root or `sudo` (the script re-execs itself via `sudo -E` if not run as root) |
| **Disk** | ~20 GB free (SecLists + PayloadsAllTheThings dominate) |
| **Network** | Stable connection (many tools build from source / clone from GitHub) |

---

## 🚀 Quick Start

```bash
git clone https://github.com/PekSec/Kali-Setup.git
cd Kali-Setup
chmod +x kali-setup.sh
sudo ./kali-setup.sh
```

### With a custom CA certificate

Pass a `.crt` as the first argument; it is installed into the system trust store:

```bash
sudo ./kali-setup.sh /path/to/your-ca.crt
```

> The `.zshrc` in this repo is copied to both the invoking user's home and `/root`. Keep the
> script and `.zshrc` together in the same directory when running.

---

## ⚙️ Configuration Flags

All are environment variables — set them before the command:

| Variable | Default | Effect |
|----------|---------|--------|
| `DRY_RUN` | `0` | Print every action without executing it. |
| `FORCE_REINSTALL` | `0` | Reinstall tools even if already present. |
| `PENTEST_YEAR` | current year | Year used for the `~/pentests/<year>.NN` monthly folders. |
| `DOCKER_DEBIAN_SUITE` | `trixie` | Debian suite for the Docker apt repo (auto-falls back to `bookworm`). |
| `APT_INSTALL_RECOMMENDS` | `1` | Set to `0` to add `--no-install-recommends`. |
| `LOG_FILE` | `~/kali-setup.log` | Log destination. |

Example — preview everything first:

```bash
sudo DRY_RUN=1 ./kali-setup.sh
```

---

## 🛠️ What Gets Installed

### Base system & toolchains
Git, curl, wget, vim, jq, fzf, unzip, p7zip · modern CLI (bat, fd-find, ripgrep, tmux, btop) ·
build-essential · OpenJDK (21, falls back to 17) · Node.js 20 · **Go** (`golang-go`) ·
**Rust** (rustup) · **Python** (python3-full, pipx) · **Docker CE** + compose plugin ·
**eza** (apt, cargo fallback).

### Security tooling by category

| Category | Tools |
|----------|-------|
| 🌐 **Web** | ffuf, httpx, katana, nuclei, dalfox *(Go)* · feroxbuster *(Rust)* · XSStrike, Corsy *(git clone)* · Arjun *(pipx)* · sqlmap *(apt)* |
| 🔍 **Recon** | subfinder, assetfinder, amass, puredns, dnsx, naabu *(Go)* · rustscan *(Rust)* |
| 🕸️ **Network** | chisel, ligolo-ng (proxy + agent) *(Go)* · rustcat *(Rust)* |
| 🔓 **Exploit / C2** | Sliver *(official installer, git-clone fallback)* · impacket *(pipx)* · metasploit-framework *(apt)* |
| 🩸 **Active Directory** | Neo4j *(apt)* · BloodHound CE *(git clone → docker compose)* · RustHound *(Rust)* · Certipy, Coercer *(pipx)* |
| 🔐 **PrivEsc** | PEASS-ng (linpeas), linux-exploit-suggester *(git clone)* |
| 🤖 **Automation** | AutoRecon *(pipx)* |
| 🔍 **OSINT** | sherlock, holehe, h8mail *(pipx)* |
| ☁️ **Cloud / Container** | trivy *(apt / official script)* · kube-hunter, ScoutSuite, Prowler *(pipx)* · CloudFox *(Go)* |
| 🔧 **Misc** | Ciphey, haiti *(pipx)* · gitleaks *(Go)* · trufflehog *(pipx, Go fallback)* |

### Wordlists (git clones into `~/wordlists/`)
fuzzdb · SecLists · PayloadsAllTheThings · Default-Accounts-Arsenal

> **Python repo tools (XSStrike, Corsy):** always cloned. The script attempts an isolated
> `pipx install` of the repo; if the repo isn't packaged for pipx, dependencies are **not**
> installed system-wide. Create a per-tool venv yourself — see [Post-Installation](#-post-installation).

---

## 🐚 Shell Environment (zsh)

The `.zshrc` in this repo is installed for both the user and root.

- **Framework:** Oh My Zsh + **Powerlevel10k** theme
- **Plugins** (loaded only if present): `git`, `sudo`, `fzf`, `docker`, `kubectl`,
  `zsh-autosuggestions`, `zsh-history-substring-search`, `zsh-syntax-highlighting`
- **Colors:** Dracula palette for syntax highlighting
- **PATH:** auto-adds `~/.local/bin`, `~/bin`, `~/go/bin`, `~/.cargo/bin`, `/usr/local/go/bin`
  (de-duplicated, only existing dirs)
- **Shared root access:** the setup writes `/root/.zshrc.local`, which `.zshrc` sources, so the
  **root** shell also gets the primary user's `~/go/bin`, `~/.cargo/bin`, and `~/.local/bin` on
  its PATH — root can run tools installed under the user without reinstalling them. Any host can
  drop its own `~/.zshrc.local` for machine-local PATH tweaks.
- **History:** 50k lines, shared across sessions, dedup + ignore-space

### Functions

| Function | Purpose |
|----------|---------|
| `update-system` | apt update / upgrade / autoremove / autoclean |
| `update-tools` | Reinstall/upgrade all Go, Rust, pipx tools + nuclei templates |
| `update-wordlists` | `git pull` every wordlist repo |
| `venv` | Activate `./venv` or `./.venv` in the current directory |
| `zsh-healthcheck` | Print shell info, PATH, and tool-availability report |
| `toolsweb`, `toolsrecon`, `toolsnetwork`, `toolsexploit`, `toolsad`, `toolsprivesc`, `toolsauto`, `toolsosint`, `toolscloud`, `toolsmisc` | `cd` into the matching `~/tools/<category>` |

### Aliases (selected)

```
ls / ll / la / tree     eza with icons (falls back to coreutils ls)
.. ... ....             cd up 1 / 2 / 3 levels
gst gco gp gps ga gc    git status/checkout/pull/push/add/commit (+ more)
dps dpsa di dex dlog    docker ps / images / exec -it / logs (+ compose: dc, dcu, dcud, dcd)
k kgp kgs kgd kl        kubectl get pods/svc/deploy, logs (+ more)
reload-zsh              source ~/.zshrc
```

---

## 📁 Directory Layout

```
~/
├── go/bin/           Go tools (in PATH)
├── .cargo/bin/       Rust tools (in PATH)
├── .local/bin/       pipx tools (in PATH)
├── wordlists/        fuzzdb, SecLists, PayloadsAllTheThings, Default-Accounts-Arsenal
├── pentests/         Monthly project folders: <YEAR>.01 … <YEAR>.12
└── tools/            Git-cloned tools + generated README.md
    ├── web/          XSStrike, Corsy
    ├── recon/        (Go tools live in ~/go/bin)
    ├── network/      (Go/Rust tools live in PATH)
    ├── exploit/      sliver/ (only if the official installer failed)
    ├── ad/           BloodHound/ (BloodHound CE — docker compose)
    ├── privesc/      PEASS-ng, linux-exploit-suggester
    ├── automation/   (AutoRecon lives in ~/.local/bin)
    ├── osint/        (pipx tools live in PATH)
    ├── cloud/        (mixed PATH locations)
    └── misc/         (mixed PATH locations)
```

Most binaries land in standard `bin` dirs already on `PATH`; `~/tools/` holds the repos that
must be run in place.

---

## 🔄 Post-Installation

After the run, the summary lists manual steps. In short:

**1. Start a new login shell** — needed for the zsh switch, the `docker` group, and PATH
changes from Go/Rust/pipx. Log out and back in.

**2. Configure API keys** (optional, for fuller results):

```bash
$EDITOR ~/.config/subfinder/provider-config.yaml
$EDITOR ~/.config/amass/config.ini
```

**3. BloodHound CE** — it is now container-based (no `npm build`):

```bash
cd ~/tools/ad/BloodHound
docker compose -f examples/docker-compose/docker-compose.yml up -d   # path may vary by release
docker compose logs bloodhound | grep -i "Initial Password"          # one-time admin password
# open http://localhost:8080 and log in as: admin
```

Collect data with RustHound (`rusthound ...`) or SharpHound, then upload the zip in the UI.
The bundled Neo4j service (`:7474`) is only for the legacy BloodHound.

**4. XSStrike / Corsy** — if dependencies were not auto-installed, make a venv yourself:

```bash
cd ~/tools/web/XSStrike
python3 -m venv .venv
.venv/bin/pip install -r requirements.txt
.venv/bin/python xsstrike.py
```

**5. Sliver** — if the official installer failed, the repo was cloned; build with `make` in
`~/tools/exploit/sliver`.

**6. Smoke test:**

```bash
httpx -version
nuclei -version
toolsweb          # should cd into ~/tools/web
zsh-healthcheck   # tool-availability overview
```

---

## 🔃 Updating

The installed `.zshrc` provides update helpers:

```bash
update-system      # apt update + upgrade + autoremove + autoclean
update-tools       # reinstall/upgrade all Go + Rust + pipx tools, refresh nuclei templates
update-wordlists   # git pull every wordlist repo
```

Or re-run the setup script — it is idempotent and will pull repos / skip satisfied tools.
Use `FORCE_REINSTALL=1` to rebuild everything.

---

## 🐛 Troubleshooting

**Read the log first** — every action is timestamped there:

```bash
grep -E 'ERROR|WARNING' ~/kali-setup.log
tail -n 50 ~/kali-setup.log
```

The end-of-run summary also lists soft errors and warnings with their return codes and the exact
command that failed, so you can re-run just that piece.

<details>
<summary><b>"command not found" right after install</b></summary>

You haven't started a new login shell yet. `source ~/.zshrc`, or log out and back in — Go/Rust/pipx
bin dirs are only added to PATH by the new `.zshrc`.
</details>

<details>
<summary><b>Docker: permission denied</b></summary>

Your session predates the `docker` group membership. Run `newgrp docker` or re-login.
</details>

<details>
<summary><b>Python tool won't run (missing modules)</b></summary>

For XSStrike/Corsy the deps may not have auto-installed (by design — no system-package breakage).
Create a venv in the tool's folder and `pip install -r requirements.txt` there. See step 4 above.
</details>

<details>
<summary><b>A tool failed but the script "finished"</b></summary>

That's the soft-fail design. Check the summary's "Soft errors" section and the log, fix the
blocker (often a transient network issue), and re-run — completed tools are skipped.
</details>

<details>
<summary><b>Neo4j not active (verification warning)</b></summary>

```bash
sudo systemctl status neo4j
sudo systemctl restart neo4j
sudo journalctl -u neo4j -n 50
```
Note: BloodHound CE brings its own database container and does not need this Neo4j service.
</details>

---

*Generated tool docs are also written to `~/tools/README.md` on each run.*
