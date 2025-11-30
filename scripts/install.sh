#!/usr/bin/env bash
#
# git-gtr Installer
# Installs the git-gtr standalone executable to ~/.local/bin (or custom location)
#
# Usage:
#   ./scripts/install.sh              # Interactive install to ~/.local/bin
#   INSTALL_DIR=/usr/local/bin sudo ./scripts/install.sh  # System-wide install
#
# Environment variables:
#   INSTALL_DIR  - Override default install location
#

set -e

# Colors (if terminal supports them)
if [ -t 1 ] && command -v tput >/dev/null 2>&1; then
  RED=$(tput setaf 1)
  GREEN=$(tput setaf 2)
  YELLOW=$(tput setaf 3)
  BLUE=$(tput setaf 4)
  BOLD=$(tput bold)
  RESET=$(tput sgr0)
else
  RED="" GREEN="" YELLOW="" BLUE="" BOLD="" RESET=""
fi

log_info() { echo "${GREEN}[OK]${RESET} $*"; }
log_warn() { echo "${YELLOW}[!]${RESET} $*"; }
log_error() { echo "${RED}[x]${RESET} $*" >&2; }
log_step() { echo "${BLUE}==>${RESET} ${BOLD}$*${RESET}"; }

# Detect OS
detect_os() {
  case "$OSTYPE" in
    darwin*) echo "macos" ;;
    linux*) echo "linux" ;;
    msys*|cygwin*|win32*) echo "windows" ;;
    *)
      case "$(uname -s 2>/dev/null)" in
        Darwin) echo "macos" ;;
        Linux) echo "linux" ;;
        MINGW*|MSYS*|CYGWIN*) echo "windows" ;;
        *) echo "unknown" ;;
      esac
      ;;
  esac
}

# Check if running as root
is_root() {
  [ "$(id -u)" -eq 0 ]
}

# Get install directory - defaults to ~/.local/bin for user convenience
get_install_dir() {
  # If user specified INSTALL_DIR, use that
  if [ -n "${INSTALL_DIR:-}" ]; then
    echo "$INSTALL_DIR"
    return
  fi

  # Default to ~/.local/bin (XDG standard, works on most systems)
  local default_dir="$HOME/.local/bin"

  # Create if it doesn't exist
  if [ ! -d "$default_dir" ]; then
    mkdir -p "$default_dir"
  fi

  echo "$default_dir"
}

# Check if a command is available
check_command() {
  command -v "$1" >/dev/null 2>&1
}

# Check Bash version
check_bash() {
  local bash_major="${BASH_VERSINFO[0]}"
  local bash_minor="${BASH_VERSINFO[1]}"

  if [ "$bash_major" -lt 3 ] || { [ "$bash_major" -eq 3 ] && [ "$bash_minor" -lt 2 ]; }; then
    return 1
  fi
  return 0
}

# Check Git version
check_git() {
  if ! check_command git; then
    return 1
  fi

  local git_version
  git_version=$(git --version 2>/dev/null | sed 's/git version //' | cut -d. -f1-2)
  local git_major git_minor
  git_major=$(echo "$git_version" | cut -d. -f1)
  git_minor=$(echo "$git_version" | cut -d. -f2)

  if [ "$git_major" -lt 2 ] || { [ "$git_major" -eq 2 ] && [ "$git_minor" -lt 5 ]; }; then
    return 1
  fi
  return 0
}

# Offer to install missing dependencies
install_dependency() {
  local dep="$1"
  local os="$2"

  echo ""
  log_step "Would you like to install $dep?"

  case "$os" in
    macos)
      if check_command brew; then
        echo "  Command: brew install $dep"
        read -p "  Install with Homebrew? [y/N] " -n 1 -r
        echo
        if [[ $REPLY =~ ^[Yy]$ ]]; then
          brew install "$dep"
          return $?
        fi
      else
        log_warn "Homebrew not found. Please install $dep manually:"
        echo "  1. Install Homebrew: /bin/bash -c \"\$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)\""
        echo "  2. Then run: brew install $dep"
      fi
      ;;
    linux)
      if check_command apt-get; then
        echo "  Command: sudo apt-get install $dep"
        read -p "  Install with apt? [y/N] " -n 1 -r
        echo
        if [[ $REPLY =~ ^[Yy]$ ]]; then
          sudo apt-get update && sudo apt-get install -y "$dep"
          return $?
        fi
      elif check_command dnf; then
        echo "  Command: sudo dnf install $dep"
        read -p "  Install with dnf? [y/N] " -n 1 -r
        echo
        if [[ $REPLY =~ ^[Yy]$ ]]; then
          sudo dnf install -y "$dep"
          return $?
        fi
      elif check_command pacman; then
        echo "  Command: sudo pacman -S $dep"
        read -p "  Install with pacman? [y/N] " -n 1 -r
        echo
        if [[ $REPLY =~ ^[Yy]$ ]]; then
          sudo pacman -S --noconfirm "$dep"
          return $?
        fi
      elif check_command yum; then
        echo "  Command: sudo yum install $dep"
        read -p "  Install with yum? [y/N] " -n 1 -r
        echo
        if [[ $REPLY =~ ^[Yy]$ ]]; then
          sudo yum install -y "$dep"
          return $?
        fi
      elif check_command apk; then
        echo "  Command: sudo apk add $dep"
        read -p "  Install with apk? [y/N] " -n 1 -r
        echo
        if [[ $REPLY =~ ^[Yy]$ ]]; then
          sudo apk add "$dep"
          return $?
        fi
      else
        log_warn "Could not detect package manager. Please install $dep manually."
      fi
      ;;
    windows)
      log_warn "Automatic installation not supported on Windows."
      echo "  Please install $dep from: https://$dep-scm.com/download/win"
      ;;
  esac

  return 1
}

# Find the git-gtr executable
find_source_file() {
  local script_dir
  script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

  # Check parent directory (repo root)
  if [ -f "$script_dir/../git-gtr" ]; then
    echo "$script_dir/../git-gtr"
    return 0
  fi

  # Check same directory
  if [ -f "$script_dir/git-gtr" ]; then
    echo "$script_dir/git-gtr"
    return 0
  fi

  # Check current directory
  if [ -f "./git-gtr" ]; then
    echo "./git-gtr"
    return 0
  fi

  return 1
}

# Main installation
main() {
  echo ""
  echo "${BOLD}git-gtr Installer${RESET}"
  echo "=================="
  echo ""

  local os
  os=$(detect_os)
  log_info "Detected OS: $os"

  # Check dependencies
  log_step "Checking dependencies..."
  echo ""

  # Check Bash
  if check_bash; then
    log_info "Bash ${BASH_VERSINFO[0]}.${BASH_VERSINFO[1]} (3.2+ required)"
  else
    log_error "Bash 3.2+ required (found: ${BASH_VERSINFO[0]}.${BASH_VERSINFO[1]})"
    if ! install_dependency "bash" "$os"; then
      log_error "Please install Bash 3.2+ and try again"
      exit 1
    fi
  fi

  # Check Git
  if check_git; then
    local git_ver
    git_ver=$(git --version 2>/dev/null | sed 's/git version //')
    log_info "Git $git_ver (2.5+ required)"
  else
    if check_command git; then
      local git_ver
      git_ver=$(git --version 2>/dev/null | sed 's/git version //')
      log_error "Git 2.5+ required (found: $git_ver)"
    else
      log_error "Git not found"
    fi
    if ! install_dependency "git" "$os"; then
      log_error "Please install Git 2.5+ and try again"
      exit 1
    fi
  fi

  echo ""

  # Find the git-gtr executable
  local source_file
  if ! source_file=$(find_source_file); then
    log_error "git-gtr executable not found"
    echo "  Expected locations:"
    echo "    - ./git-gtr (repo root)"
    echo "    - ../git-gtr (if running from scripts/)"
    exit 1
  fi
  source_file="$(cd "$(dirname "$source_file")" && pwd)/$(basename "$source_file")"

  # Get install directory
  local install_dir
  install_dir=$(get_install_dir)
  local install_path="$install_dir/git-gtr"

  log_step "Installing git-gtr..."
  echo "  Source: $source_file"
  echo "  Destination: $install_path"
  echo ""

  # Check if already installed
  if [ -f "$install_path" ]; then
    local existing_version=""
    existing_version=$("$install_path" --version 2>/dev/null | awk '{print $4}' || echo "unknown")
    local new_version=""
    new_version=$("$source_file" --version 2>/dev/null | awk '{print $4}' || echo "unknown")

    log_warn "git-gtr already exists at $install_path (v$existing_version)"
    echo "  New version: v$new_version"
    read -p "  Overwrite? [y/N] " -n 1 -r
    echo
    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
      log_info "Installation cancelled"
      exit 0
    fi
  fi

  # Create directory if needed
  if [ ! -d "$install_dir" ]; then
    mkdir -p "$install_dir"
  fi

  # Copy the file
  if is_root || [ -w "$install_dir" ]; then
    cp "$source_file" "$install_path"
    chmod +x "$install_path"
  else
    log_warn "Need sudo to write to $install_dir"
    sudo cp "$source_file" "$install_path"
    sudo chmod +x "$install_path"
  fi

  log_info "Installed: $install_path"

  # Check if install_dir is in PATH
  if ! echo "$PATH" | tr ':' '\n' | grep -qx "$install_dir"; then
    echo ""
    log_warn "$install_dir is not in your PATH"
    echo ""
    echo "  Add this to your shell config:"
    echo ""

    # Detect shell and give appropriate advice
    local shell_name
    shell_name=$(basename "${SHELL:-bash}")
    case "$shell_name" in
      zsh)
        echo "    echo 'export PATH=\"\$HOME/.local/bin:\$PATH\"' >> ~/.zshrc"
        echo "    source ~/.zshrc"
        ;;
      fish)
        echo "    fish_add_path ~/.local/bin"
        ;;
      *)
        echo "    echo 'export PATH=\"\$HOME/.local/bin:\$PATH\"' >> ~/.bashrc"
        echo "    source ~/.bashrc"
        ;;
    esac
    echo ""
  fi

  echo ""
  log_step "Installation complete!"
  echo ""
  echo "  Usage:"
  echo "    git gtr new <branch>      # Create worktree"
  echo "    git gtr editor <branch>   # Open in editor"
  echo "    git gtr ai <branch>       # Start AI tool"
  echo "    git gtr --help            # Show all commands"
  echo ""
  echo "  Quick setup (run in your git repo):"
  echo "    git gtr config set gtr.editor.default cursor"
  echo "    git gtr config set gtr.ai.default claude"
  echo ""

  # Verify installation
  if check_command git-gtr; then
    log_info "Verification: git-gtr is accessible"
    echo "  Version: $(git-gtr --version)"
  else
    log_warn "git-gtr not found in PATH yet. You may need to:"
    echo "  1. Add $install_dir to PATH (see above)"
    echo "  2. Restart your terminal"
  fi
}

# Run installer
main "$@"
