#!/usr/bin/env bash
#
# Build script for standalone git-gtr executable
# This merges all shell files from git-worktree-runner into a single portable script
#
# Usage:
#   .github/scripts/build-standalone.sh [--source-dir <path>] [--output <path>]
#
# Options:
#   --source-dir  Path to git-worktree-runner source (default: clones from GitHub)
#   --output      Output file path (default: ./git-gtr)
#

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"

# Defaults
SOURCE_DIR=""
OUTPUT_FILE="${REPO_ROOT}/git-gtr"
CLEANUP_SOURCE=0

# Parse arguments
while [[ $# -gt 0 ]]; do
  case $1 in
    --source-dir)
      SOURCE_DIR="$2"
      shift 2
      ;;
    --output)
      OUTPUT_FILE="$2"
      shift 2
      ;;
    -h|--help)
      echo "Usage: $0 [--source-dir <path>] [--output <path>]"
      echo ""
      echo "Options:"
      echo "  --source-dir  Path to git-worktree-runner source (default: clones from GitHub)"
      echo "  --output      Output file path (default: ./git-gtr)"
      exit 0
      ;;
    *)
      echo "Unknown option: $1" >&2
      exit 1
      ;;
  esac
done

# Clone source if not provided
if [ -z "$SOURCE_DIR" ]; then
  SOURCE_DIR=$(mktemp -d)
  CLEANUP_SOURCE=1
  echo "Cloning git-worktree-runner..."
  git clone --depth 1 https://github.com/coderabbitai/git-worktree-runner.git "$SOURCE_DIR" 2>/dev/null
fi

# Verify source directory
if [ ! -f "$SOURCE_DIR/bin/gtr" ]; then
  echo "Error: Invalid source directory - bin/gtr not found" >&2
  exit 1
fi

VERSION=$(grep 'GTR_VERSION=' "${SOURCE_DIR}/bin/gtr" | head -1 | cut -d'"' -f2)

echo "Building git-gtr standalone v${VERSION}..."
echo "  Source: $SOURCE_DIR"
echo "  Output: $OUTPUT_FILE"

# Create output directory if needed
mkdir -p "$(dirname "$OUTPUT_FILE")"

# Start building the bundled script
cat > "$OUTPUT_FILE" << 'HEADER'
#!/usr/bin/env bash
#
# git-gtr - Git Worktree Runner (Standalone Edition)
# https://github.com/coderabbitai/git-worktree-runner
#
# This is a single-file distribution that bundles all dependencies.
# Licensed under Apache 2.0
#

set -e

# ============================================================================
# DEPENDENCY CHECKS
# ============================================================================

GTR_STANDALONE=1

check_dependencies() {
  local missing=0
  local install_hint=""

  # Detect OS for install hints
  local os=""
  case "$OSTYPE" in
    darwin*) os="macos" ;;
    linux*) os="linux" ;;
    msys*|cygwin*|win32*) os="windows" ;;
  esac

  # Check Bash version (3.2+ required)
  local bash_version="${BASH_VERSINFO[0]}.${BASH_VERSINFO[1]}"
  local bash_major="${BASH_VERSINFO[0]}"

  if [ "$bash_major" -lt 3 ] || { [ "$bash_major" -eq 3 ] && [ "${BASH_VERSINFO[1]}" -lt 2 ]; }; then
    echo "[x] Bash 3.2+ required (found: $bash_version)" >&2
    missing=1
    case "$os" in
      macos) install_hint="$install_hint\n  brew install bash" ;;
      linux) install_hint="$install_hint\n  sudo apt-get install bash  # Debian/Ubuntu\n  sudo dnf install bash       # Fedora" ;;
    esac
  fi

  # Check Git (2.5+ required for worktree support)
  if ! command -v git >/dev/null 2>&1; then
    echo "[x] Git not found" >&2
    missing=1
    case "$os" in
      macos) install_hint="$install_hint\n  brew install git  # or: xcode-select --install" ;;
      linux) install_hint="$install_hint\n  sudo apt-get install git  # Debian/Ubuntu\n  sudo dnf install git       # Fedora" ;;
      windows) install_hint="$install_hint\n  Download from https://git-scm.com/download/win" ;;
    esac
  else
    # Check Git version
    local git_version_full
    git_version_full=$(git --version 2>/dev/null | sed 's/git version //')
    local git_major git_minor
    git_major=$(echo "$git_version_full" | cut -d. -f1)
    git_minor=$(echo "$git_version_full" | cut -d. -f2)

    if [ "$git_major" -lt 2 ] || { [ "$git_major" -eq 2 ] && [ "$git_minor" -lt 5 ]; }; then
      echo "[x] Git 2.5+ required for worktree support (found: $git_version_full)" >&2
      missing=1
      case "$os" in
        macos) install_hint="$install_hint\n  brew upgrade git" ;;
        linux) install_hint="$install_hint\n  sudo apt-get update && sudo apt-get install git" ;;
      esac
    fi
  fi

  if [ "$missing" -eq 1 ]; then
    echo "" >&2
    echo "Missing dependencies. Install with:" >&2
    echo -e "$install_hint" >&2
    echo "" >&2
    exit 1
  fi
}

# Run dependency check on first invocation (skip for --version/--help)
case "${1:-}" in
  version|--version|-v) ;;
  help|--help|-h) ;;
  *) check_dependencies ;;
esac

HEADER

# Add version
echo "" >> "$OUTPUT_FILE"
echo "# Version" >> "$OUTPUT_FILE"
echo "GTR_VERSION=\"${VERSION}\"" >> "$OUTPUT_FILE"
echo "" >> "$OUTPUT_FILE"

# ============================================================================
# EMBED LIBRARY FILES
# ============================================================================

echo "# ============================================================================" >> "$OUTPUT_FILE"
echo "# EMBEDDED LIBRARIES" >> "$OUTPUT_FILE"
echo "# ============================================================================" >> "$OUTPUT_FILE"
echo "" >> "$OUTPUT_FILE"

for lib in ui config platform core copy hooks; do
  echo "# --- lib/${lib}.sh ---" >> "$OUTPUT_FILE"
  # Strip shebang and leading comments, keep the code
  tail -n +2 "${SOURCE_DIR}/lib/${lib}.sh" >> "$OUTPUT_FILE"
  echo "" >> "$OUTPUT_FILE"
done

# ============================================================================
# EMBED ADAPTERS AS FUNCTIONS
# ============================================================================

echo "# ============================================================================" >> "$OUTPUT_FILE"
echo "# EMBEDDED ADAPTERS" >> "$OUTPUT_FILE"
echo "# ============================================================================" >> "$OUTPUT_FILE"
echo "" >> "$OUTPUT_FILE"

# Create adapter registry functions
echo "# Editor adapter registry" >> "$OUTPUT_FILE"
echo "_gtr_load_editor_adapter_embedded() {" >> "$OUTPUT_FILE"
echo "  local editor=\"\$1\"" >> "$OUTPUT_FILE"
echo "  case \"\$editor\" in" >> "$OUTPUT_FILE"

EDITOR_ADAPTERS=""
for adapter_file in "${SOURCE_DIR}"/adapters/editor/*.sh; do
  adapter_name=$(basename "$adapter_file" .sh)
  EDITOR_ADAPTERS="$EDITOR_ADAPTERS $adapter_name"
  echo "    ${adapter_name})" >> "$OUTPUT_FILE"
  grep -v '^#' "$adapter_file" | grep -v '^$' | sed 's/^/      /' >> "$OUTPUT_FILE"
  echo "      return 0" >> "$OUTPUT_FILE"
  echo "      ;;" >> "$OUTPUT_FILE"
done

echo "    *)" >> "$OUTPUT_FILE"
echo "      return 1" >> "$OUTPUT_FILE"
echo "      ;;" >> "$OUTPUT_FILE"
echo "  esac" >> "$OUTPUT_FILE"
echo "}" >> "$OUTPUT_FILE"
echo "" >> "$OUTPUT_FILE"

# AI adapter registry
echo "# AI adapter registry" >> "$OUTPUT_FILE"
echo "_gtr_load_ai_adapter_embedded() {" >> "$OUTPUT_FILE"
echo "  local ai_tool=\"\$1\"" >> "$OUTPUT_FILE"
echo "  case \"\$ai_tool\" in" >> "$OUTPUT_FILE"

AI_ADAPTERS=""
for adapter_file in "${SOURCE_DIR}"/adapters/ai/*.sh; do
  adapter_name=$(basename "$adapter_file" .sh)
  AI_ADAPTERS="$AI_ADAPTERS $adapter_name"
  echo "    ${adapter_name})" >> "$OUTPUT_FILE"
  grep -v '^#' "$adapter_file" | grep -v '^$' | sed 's/^/      /' >> "$OUTPUT_FILE"
  echo "      return 0" >> "$OUTPUT_FILE"
  echo "      ;;" >> "$OUTPUT_FILE"
done

echo "    *)" >> "$OUTPUT_FILE"
echo "      return 1" >> "$OUTPUT_FILE"
echo "      ;;" >> "$OUTPUT_FILE"
echo "  esac" >> "$OUTPUT_FILE"
echo "}" >> "$OUTPUT_FILE"
echo "" >> "$OUTPUT_FILE"

# ============================================================================
# EMBED MAIN SCRIPT (modified)
# ============================================================================

echo "# ============================================================================" >> "$OUTPUT_FILE"
echo "# MAIN SCRIPT" >> "$OUTPUT_FILE"
echo "# ============================================================================" >> "$OUTPUT_FILE"
echo "" >> "$OUTPUT_FILE"

# Add generic adapter fallback functions
cat >> "$OUTPUT_FILE" << 'GENERIC_ADAPTERS'
# Generic adapter functions (used when no explicit adapter file exists)
# These will be overridden if an adapter is loaded
# Globals set by load_editor_adapter: GTR_EDITOR_CMD, GTR_EDITOR_CMD_NAME
editor_can_open() {
  command -v "$GTR_EDITOR_CMD_NAME" >/dev/null 2>&1
}

editor_open() {
  # $GTR_EDITOR_CMD may contain arguments (e.g., "code --wait")
  eval "$GTR_EDITOR_CMD \"\$1\""
}

# Globals set by load_ai_adapter: GTR_AI_CMD, GTR_AI_CMD_NAME
ai_can_start() {
  command -v "$GTR_AI_CMD_NAME" >/dev/null 2>&1
}

ai_start() {
  local path="$1"
  shift
  (cd "$path" && eval "$GTR_AI_CMD \"\$@\"")
}

# Modified load_editor_adapter for standalone mode
load_editor_adapter() {
  local editor="$1"

  # Try loading embedded adapter first
  if _gtr_load_editor_adapter_embedded "$editor"; then
    return 0
  fi

  # Generic fallback: check if command exists in PATH
  local cmd_name="${editor%% *}"

  if ! command -v "$cmd_name" >/dev/null 2>&1; then
    log_error "Editor '$editor' not found"
    log_info "Built-in adapters: cursor, vscode, zed, idea, pycharm, webstorm, vim, nvim, emacs, sublime, nano, atom"
    log_info "Or use any editor command available in your PATH"
    exit 1
  fi

  GTR_EDITOR_CMD="$editor"
  GTR_EDITOR_CMD_NAME="$cmd_name"
}

# Modified load_ai_adapter for standalone mode
load_ai_adapter() {
  local ai_tool="$1"

  # Try loading embedded adapter first
  if _gtr_load_ai_adapter_embedded "$ai_tool"; then
    return 0
  fi

  # Generic fallback: check if command exists in PATH
  local cmd_name="${ai_tool%% *}"

  if ! command -v "$cmd_name" >/dev/null 2>&1; then
    log_error "AI tool '$ai_tool' not found"
    log_info "Built-in adapters: aider, claude, codex, continue, cursor, gemini, opencode"
    log_info "Or use any AI tool command available in your PATH"
    exit 1
  fi

  GTR_AI_CMD="$ai_tool"
  GTR_AI_CMD_NAME="$cmd_name"
}

GENERIC_ADAPTERS

# Extract main script (from main() to end, excluding functions we replaced)
main_start=$(grep -n '^main()' "${SOURCE_DIR}/bin/gtr" | cut -d: -f1)

awk -v start="$main_start" '
  NR >= start {
    if (/^load_editor_adapter\(\)/) { skip=1 }
    if (/^load_ai_adapter\(\)/) { skip=1 }
    if (/^cmd_adapter\(\)/) { skip=1 }
    if (skip && /^}$/) { skip=0; next }
    if (/^main "\$@"$/) { next }
    if (!skip) print
  }
' "${SOURCE_DIR}/bin/gtr" >> "$OUTPUT_FILE"

# Add standalone-compatible cmd_adapter function
# Use the actual discovered adapters
cat >> "$OUTPUT_FILE" << CMD_ADAPTER_STANDALONE

# Adapter command (standalone version with embedded adapters)
cmd_adapter() {
  echo "Available Adapters"
  echo ""

  echo "Editor Adapters:"
  echo ""
  printf "%-15s %-15s %s\n" "NAME" "STATUS" "NOTES"
  printf "%-15s %-15s %s\n" "---------------" "---------------" "-----"

  for adapter_name in${EDITOR_ADAPTERS}; do
    if _gtr_load_editor_adapter_embedded "\$adapter_name"; then
      if editor_can_open 2>/dev/null; then
        printf "%-15s %-15s %s\n" "\$adapter_name" "[ready]" ""
      else
        printf "%-15s %-15s %s\n" "\$adapter_name" "[missing]" "Not found in PATH"
      fi
    fi
  done

  echo ""
  echo ""
  echo "AI Tool Adapters:"
  echo ""
  printf "%-15s %-15s %s\n" "NAME" "STATUS" "NOTES"
  printf "%-15s %-15s %s\n" "---------------" "---------------" "-----"

  for adapter_name in${AI_ADAPTERS}; do
    if _gtr_load_ai_adapter_embedded "\$adapter_name"; then
      if ai_can_start 2>/dev/null; then
        printf "%-15s %-15s %s\n" "\$adapter_name" "[ready]" ""
      else
        printf "%-15s %-15s %s\n" "\$adapter_name" "[missing]" "Not found in PATH"
      fi
    fi
  done

  echo ""
  echo ""
  echo "Tip: Set defaults with:"
  echo "   git gtr config set gtr.editor.default <name>"
  echo "   git gtr config set gtr.ai.default <name>"
}
CMD_ADAPTER_STANDALONE

# Add the main invocation at the very end
echo '' >> "$OUTPUT_FILE"
echo '# Run main' >> "$OUTPUT_FILE"
echo 'main "$@"' >> "$OUTPUT_FILE"

# Make executable
chmod +x "$OUTPUT_FILE"

# Cleanup temp directory if we cloned
if [ "$CLEANUP_SOURCE" -eq 1 ]; then
  rm -rf "$SOURCE_DIR"
fi

# Show results
size=$(wc -c < "$OUTPUT_FILE" | tr -d ' ')
lines=$(wc -l < "$OUTPUT_FILE" | tr -d ' ')

echo ""
echo "Build complete!"
echo "  Output: $OUTPUT_FILE"
echo "  Size: ${lines} lines, ${size} bytes"
echo "  Version: ${VERSION}"
