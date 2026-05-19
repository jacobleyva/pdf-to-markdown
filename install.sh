#!/usr/bin/env bash
#
# install.sh — cross-platform setup for pdf-to-markdown
#
# Installs pandoc using the appropriate package manager for the detected OS,
# creates a Python virtual environment, and installs Python dependencies.
#
# Supports:
#   - macOS / Linux with Homebrew (brew)
#   - Fedora (dnf)
#   - Immutable Fedora variants — Bazzite, Silverblue, Kinoite (advisory)
#   - Debian / Ubuntu (apt-get)
#   - Arch Linux (pacman)
#
# Requirements:
#   - Python >= 3.11
#   - bash
#
# Usage:
#   ./install.sh
#

set -euo pipefail

# ---------------------------------------------------------------------------
# Paths
# ---------------------------------------------------------------------------
SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
VENV_DIR="${SCRIPT_DIR}/venv"
REQUIREMENTS_FILE="${SCRIPT_DIR}/requirements.txt"

# ---------------------------------------------------------------------------
# Output helpers
# ---------------------------------------------------------------------------
info()  { printf '[install] %s\n' "$*"; }
warn()  { printf '[install] WARN: %s\n' "$*" >&2; }
err()   { printf '[install] ERROR: %s\n' "$*" >&2; }

# Print and run a privileged command. NEVER run sudo silently — always show
# the exact command and the reason before invoking it.
run_sudo() {
    local reason="$1"
    shift
    info "About to run privileged command: ${reason}"
    info "Command: sudo $*"
    sudo "$@"
}

# ---------------------------------------------------------------------------
# OS detection
# ---------------------------------------------------------------------------
OS_ID=""
OS_ID_LIKE=""
UNAME_S="$(uname -s 2>/dev/null || echo unknown)"
IS_IMMUTABLE_FEDORA="no"

detect_os() {
    if [ -r /etc/os-release ]; then
        # shellcheck disable=SC1091
        . /etc/os-release
        OS_ID="${ID:-}"
        OS_ID_LIKE="${ID_LIKE:-}"
    fi

    # Detect ostree-based (immutable) Fedora variants: Bazzite, Silverblue,
    # Kinoite, Sericea, etc. These cannot use plain `dnf install` for system
    # packages.
    if [ -f /run/ostree-booted ]; then
        IS_IMMUTABLE_FEDORA="yes"
    fi

    info "Detected: uname=${UNAME_S} ID=${OS_ID:-?} ID_LIKE=${OS_ID_LIKE:-?} immutable=${IS_IMMUTABLE_FEDORA}"
}

id_like_contains() {
    local needle="$1"
    case " ${OS_ID_LIKE} " in
        *" ${needle} "*) return 0 ;;
        *) return 1 ;;
    esac
}

# ---------------------------------------------------------------------------
# Python version check
# ---------------------------------------------------------------------------
check_python() {
    if ! command -v python3 >/dev/null 2>&1; then
        err "python3 not found in PATH. Install Python >= 3.11 and re-run."
        exit 1
    fi

    local version_str major minor
    version_str="$(python3 --version 2>&1 | awk '{print $2}')"
    major="$(printf '%s' "$version_str" | cut -d. -f1)"
    minor="$(printf '%s' "$version_str" | cut -d. -f2)"

    if [ -z "$major" ] || [ -z "$minor" ]; then
        err "Could not parse Python version from: ${version_str}"
        exit 1
    fi

    if [ "$major" -lt 3 ] || { [ "$major" -eq 3 ] && [ "$minor" -lt 11 ]; }; then
        err "Python ${version_str} is too old. Need Python >= 3.11."
        err "Install a newer Python and re-run this script."
        exit 1
    fi

    info "Python ${version_str} OK (>= 3.11)."
}

# ---------------------------------------------------------------------------
# Pandoc install
# ---------------------------------------------------------------------------
pandoc_installed() {
    command -v pandoc >/dev/null 2>&1
}

install_pandoc() {
    if pandoc_installed; then
        info "pandoc already installed at: $(command -v pandoc) — skipping install."
        return 0
    fi

    # Preferred path: Homebrew works on macOS and Linux. If brew is on PATH,
    # use it regardless of the underlying distro — this is the cleanest
    # option on immutable Fedora variants.
    if command -v brew >/dev/null 2>&1; then
        info "Using Homebrew to install pandoc."
        brew install pandoc
        return 0
    fi

    # Immutable Fedora variants (Bazzite, Silverblue, Kinoite, etc.). These
    # do not support `dnf install` for system packages. Advise the user.
    if [ "$IS_IMMUTABLE_FEDORA" = "yes" ]; then
        err "Detected an immutable Fedora variant (ostree-booted)."
        err "Examples: Bazzite, Silverblue, Kinoite, Sericea."
        err ""
        err "Recommended options for installing pandoc:"
        err "  1. Install Homebrew, then: brew install pandoc"
        err "     https://brew.sh"
        err "  2. Layer with rpm-ostree (requires reboot):"
        err "     sudo rpm-ostree install pandoc"
        err "  3. Use a toolbox/distrobox container with regular Fedora."
        err ""
        err "Re-run this script after pandoc is on PATH."
        exit 1
    fi

    # Regular Fedora / RHEL-family
    if [ "$OS_ID" = "fedora" ] || id_like_contains "fedora" || id_like_contains "rhel"; then
        run_sudo "install pandoc via dnf (Fedora/RHEL family)" \
            dnf install -y pandoc
        return 0
    fi

    # Debian / Ubuntu
    if [ "$OS_ID" = "ubuntu" ] || [ "$OS_ID" = "debian" ] || id_like_contains "debian" || id_like_contains "ubuntu"; then
        run_sudo "refresh apt package index before installing pandoc" \
            apt-get update
        run_sudo "install pandoc via apt-get (Debian/Ubuntu family)" \
            apt-get install -y pandoc
        return 0
    fi

    # Arch Linux
    if [ "$OS_ID" = "arch" ] || id_like_contains "arch"; then
        run_sudo "install pandoc via pacman (Arch family)" \
            pacman -S --noconfirm pandoc
        return 0
    fi

    # Unsupported
    err "Unsupported distribution: ID=${OS_ID:-unknown} ID_LIKE=${OS_ID_LIKE:-unknown}"
    err "Install pandoc manually and re-run this script."
    err "See: https://pandoc.org/installing.html"
    exit 1
}

# ---------------------------------------------------------------------------
# Python venv + dependencies
# ---------------------------------------------------------------------------
setup_venv() {
    if [ ! -f "$REQUIREMENTS_FILE" ]; then
        err "requirements.txt not found at: ${REQUIREMENTS_FILE}"
        err "Run this script from the pdf-to-markdown repo root."
        exit 1
    fi

    if [ -d "$VENV_DIR" ]; then
        info "Reusing existing venv at: ${VENV_DIR}"
    else
        info "Creating Python venv at: ${VENV_DIR}"
        python3 -m venv "$VENV_DIR"
    fi

    info "Upgrading pip inside venv."
    # shellcheck disable=SC1091
    . "${VENV_DIR}/bin/activate"
    python -m pip install --upgrade pip

    info "Installing Python dependencies from requirements.txt."
    python -m pip install -r "$REQUIREMENTS_FILE"

    deactivate || true
}

# ---------------------------------------------------------------------------
# Main
# ---------------------------------------------------------------------------
main() {
    info "pdf-to-markdown installer starting."
    info "Repo directory: ${SCRIPT_DIR}"

    detect_os
    check_python
    install_pandoc
    setup_venv

    info ""
    info "Setup complete."
    info ""
    info "To use pdf-to-markdown, activate the venv and run the CLI:"
    info "  source ${VENV_DIR}/bin/activate"
    info "  ./pdf2md <input.pdf>"
    info ""
    info "Or for batch conversion:"
    info "  ./pdf2md --batch <input-dir>/"
    info ""
    info "First run will download Docling AI models (~1GB). Allow time."
}

main "$@"
