#!/usr/bin/env bash
#
# Build script for standalone worktree-cli executable
# This merges all shell files from git-worktree-runner into a single portable script
#
# Usage:
#   .github/scripts/build-standalone.sh [--source-dir <path>] [--output <path>] [--shim-output <path>]
#
# Options:
#   --source-dir  Path to git-worktree-runner source (default: clones from GitHub)
#   --output      Output binary path (default: ./worktree-cli)
#   --shim-output Output git-gtr compatibility shim path (default: ./git-gtr)
#

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"

# Defaults
SOURCE_DIR=""
OUTPUT_FILE="${REPO_ROOT}/worktree-cli"
SHIM_FILE="${REPO_ROOT}/git-gtr"
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
    --shim-output)
      SHIM_FILE="$2"
      shift 2
      ;;
    -h|--help)
      echo "Usage: $0 [--source-dir <path>] [--output <path>] [--shim-output <path>]"
      echo ""
      echo "Options:"
      echo "  --source-dir  Path to git-worktree-runner source (default: clones from GitHub)"
      echo "  --output      Output binary path (default: ./worktree-cli)"
      echo "  --shim-output Output git-gtr compatibility shim path (default: ./git-gtr)"
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

# Verify source directory and select entrypoint
MAIN_ENTRY=""
if [ -f "$SOURCE_DIR/bin/git-gtr" ]; then
  MAIN_ENTRY="$SOURCE_DIR/bin/git-gtr"
elif [ -f "$SOURCE_DIR/bin/gtr" ]; then
  MAIN_ENTRY="$SOURCE_DIR/bin/gtr"
else
  echo "Error: Invalid source directory - expected bin/git-gtr or bin/gtr" >&2
  exit 1
fi

VERSION=$(grep -E 'GTR_VERSION=' "${MAIN_ENTRY}" | head -1 | sed -E 's/.*GTR_VERSION="?([^" ]+)"?.*/\1/' || true)
if [ -z "$VERSION" ]; then
  VERSION=$(bash "${MAIN_ENTRY}" --version 2>/dev/null | awk '{print $NF}' || true)
fi
if [ -z "$VERSION" ]; then
  echo "Error: Unable to determine upstream version" >&2
  exit 1
fi

echo "Building worktree-cli standalone v${VERSION}..."
echo "  Source: $SOURCE_DIR"
echo "  Output: $OUTPUT_FILE"
echo "  Shim:   $SHIM_FILE"

# Create output directory if needed
mkdir -p "$(dirname "$OUTPUT_FILE")"
mkdir -p "$(dirname "$SHIM_FILE")"

# Start building the bundled script
cat > "$OUTPUT_FILE" << 'HEADER'
#!/usr/bin/env bash
#
# worktree-cli - Git Worktree Runner (Standalone Edition)
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
GTR_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

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

for lib in ui args config platform core copy hooks provider adapters launch; do
  [ -f "${SOURCE_DIR}/lib/${lib}.sh" ] || continue
  echo "# --- lib/${lib}.sh ---" >> "$OUTPUT_FILE"
  # Strip shebang, then remove dead functions from vendored upstream libs.
  python3 - "${SOURCE_DIR}/lib/${lib}.sh" <<'PY' >> "$OUTPUT_FILE"
from pathlib import Path
import re
import sys

DEAD = {"cfg_bool", "spawn_terminal_in", "list_worktrees", "copy_file"}
source_file = Path(sys.argv[1])
lines = source_file.read_text().splitlines(keepends=True)

if lines and lines[0].startswith("#!"):
    lines = lines[1:]

out = []
i = 0

while i < len(lines):
    line = lines[i]
    m = re.match(r'^([A-Za-z_][A-Za-z0-9_]*)\(\)\s*\{$', line)
    if m and m.group(1) in DEAD:
        depth = line.count('{') - line.count('}')
        i += 1
        while i < len(lines) and depth > 0:
            depth += lines[i].count('{') - lines[i].count('}')
            i += 1
        while i < len(lines) and lines[i].strip() == "":
            i += 1
        continue

    out.append(line)
    i += 1

sys.stdout.write("".join(out))
PY
  echo "" >> "$OUTPUT_FILE"
done

# ============================================================================
# EMBED COMMAND HANDLERS
# ============================================================================

echo "# ============================================================================" >> "$OUTPUT_FILE"
echo "# EMBEDDED COMMANDS" >> "$OUTPUT_FILE"
echo "# ============================================================================" >> "$OUTPUT_FILE"
echo "" >> "$OUTPUT_FILE"

if [ -d "${SOURCE_DIR}/lib/commands" ]; then
  for cmd_file in "${SOURCE_DIR}"/lib/commands/*.sh; do
    [ -f "$cmd_file" ] || continue
    echo "# --- lib/commands/$(basename "$cmd_file") ---" >> "$OUTPUT_FILE"
    python3 - "$cmd_file" <<'PY' >> "$OUTPUT_FILE"
from pathlib import Path
import sys

source_file = Path(sys.argv[1])
lines = source_file.read_text().splitlines(keepends=True)
if lines and lines[0].startswith("#!"):
    lines = lines[1:]
sys.stdout.write("".join(lines))
PY
    echo "" >> "$OUTPUT_FILE"
  done
fi

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
  local entry

  # Try loading embedded adapter first
  if _gtr_load_editor_adapter_embedded "$editor"; then
    return 0
  fi

  # Try upstream registry-based adapter definitions
  if entry=$(_registry_lookup "$_EDITOR_REGISTRY" "$editor" 2>/dev/null); then
    _load_from_editor_registry "$entry"
    return 0
  fi

  # Generic fallback: check if command exists in PATH
  local cmd_name="${editor%% *}"

  if ! command -v "$cmd_name" >/dev/null 2>&1; then
    local builtin_names
    builtin_names="$(_list_registry_names "$_EDITOR_REGISTRY")"
    log_error "Editor '$editor' not found"
    log_info "Built-in adapters: $builtin_names"
    log_info "Or use any editor command available in your PATH"
    return 1
  fi

  GTR_EDITOR_CMD="$editor"
  GTR_EDITOR_CMD_NAME="$cmd_name"
}

# Modified load_ai_adapter for standalone mode
load_ai_adapter() {
  local ai_tool="$1"
  local entry

  # Try loading embedded adapter first
  if _gtr_load_ai_adapter_embedded "$ai_tool"; then
    return 0
  fi

  # Try upstream registry-based adapter definitions
  if entry=$(_registry_lookup "$_AI_REGISTRY" "$ai_tool" 2>/dev/null); then
    _load_from_ai_registry "$entry"
    return 0
  fi

  # Generic fallback: check if command exists in PATH
  local cmd_name="${ai_tool%% *}"

  if ! command -v "$cmd_name" >/dev/null 2>&1; then
    local builtin_names
    builtin_names="$(_list_registry_names "$_AI_REGISTRY")"
    log_error "AI tool '$ai_tool' not found"
    log_info "Built-in adapters: $builtin_names"
    log_info "Or use any AI tool command available in your PATH"
    return 1
  fi

  GTR_AI_CMD="$ai_tool"
  GTR_AI_CMD_NAME="$cmd_name"
}

GENERIC_ADAPTERS

# Extract main script (from main() to end, excluding functions we replaced)
main_start=$(grep -n '^main()' "${MAIN_ENTRY}" | cut -d: -f1)

awk -v start="$main_start" '
  NR >= start {
    if (/^load_editor_adapter\(\)/) { skip=1 }
    if (/^load_ai_adapter\(\)/) { skip=1 }
    if (/^cmd_adapter\(\)/) { skip=1 }
    if (skip && /^}$/) { skip=0; next }
    if (/^main "\$@"$/) { next }
    if (!skip) print
  }
' "${MAIN_ENTRY}" | sed 's/git gtr/worktree-cli/g' >> "$OUTPUT_FILE"

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

  local listed=" "
  local line adapter_name
  while IFS= read -r line; do
    [ -z "\$line" ] && continue
    adapter_name="\${line%%|*}"
    listed="\$listed\$adapter_name "
    _load_from_editor_registry "\$line"
    if editor_can_open 2>/dev/null; then
      printf "%-15s %-15s %s\n" "\$adapter_name" "[ready]" ""
    else
      printf "%-15s %-15s %s\n" "\$adapter_name" "[missing]" "Not found in PATH"
    fi
  done <<EOF
\$_EDITOR_REGISTRY
EOF

  for adapter_name in${EDITOR_ADAPTERS}; do
    case "\$listed" in *" \$adapter_name "*) continue ;; esac
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

  listed=" "
  while IFS= read -r line; do
    [ -z "\$line" ] && continue
    adapter_name="\${line%%|*}"
    listed="\$listed\$adapter_name "
    _load_from_ai_registry "\$line"
    if ai_can_start 2>/dev/null; then
      printf "%-15s %-15s %s\n" "\$adapter_name" "[ready]" ""
    else
      printf "%-15s %-15s %s\n" "\$adapter_name" "[missing]" "Not found in PATH"
    fi
  done <<EOF
\$_AI_REGISTRY
EOF

  for adapter_name in${AI_ADAPTERS}; do
    case "\$listed" in *" \$adapter_name "*) continue ;; esac
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
  echo "   worktree-cli config set gtr.editor.default <name>"
  echo "   worktree-cli config set gtr.ai.default <name>"
}
CMD_ADAPTER_STANDALONE

# Doctor command (standalone-safe adapter checks)
cat >> "$OUTPUT_FILE" << 'CMD_DOCTOR_STANDALONE'
cmd_doctor() {
  echo "Running worktree-cli health check..."
  echo ""

  local issues=0

  if command -v git >/dev/null 2>&1; then
    local git_version
    git_version=$(git --version)
    echo "[OK] Git: $git_version"
  else
    echo "[x] Git: not found"
    issues=$((issues + 1))
  fi

  local repo_root
  if repo_root=$(discover_repo_root 2>/dev/null); then
    echo "[OK] Repository: $repo_root"

    local base_dir prefix
    base_dir=$(resolve_base_dir "$repo_root")
    prefix=$(cfg_default gtr.worktrees.prefix GTR_WORKTREES_PREFIX "")

    if [ -d "$base_dir" ]; then
      local count
      count=$(find "$base_dir" -maxdepth 1 -type d -name "${prefix}*" 2>/dev/null | wc -l | tr -d ' ')
      echo "[OK] Worktrees directory: $base_dir ($count worktrees)"
    else
      echo "[i] Worktrees directory: $base_dir (not created yet)"
    fi
  else
    echo "[x] Not in a git repository"
    issues=$((issues + 1))
  fi

  local editor
  editor=$(cfg_default gtr.editor.default GTR_EDITOR_DEFAULT "none")
  if [ "$editor" != "none" ]; then
    local editor_cmd="${editor%% *}"
    if _gtr_load_editor_adapter_embedded "$editor" 2>/dev/null; then
      if editor_can_open 2>/dev/null; then
        echo "[OK] Editor: $editor (found)"
      else
        echo "[!] Editor: $editor (configured but not found in PATH)"
      fi
    elif command -v "$editor_cmd" >/dev/null 2>&1; then
      echo "[OK] Editor: $editor (found)"
    else
      echo "[!] Editor: $editor (configured but not found in PATH)"
    fi
  else
    echo "[i] Editor: none configured"
  fi

  local ai_tool
  ai_tool=$(cfg_default gtr.ai.default GTR_AI_DEFAULT "none")
  if [ "$ai_tool" != "none" ]; then
    local ai_cmd="${ai_tool%% *}"
    if _gtr_load_ai_adapter_embedded "$ai_tool" 2>/dev/null; then
      if ai_can_start 2>/dev/null; then
        echo "[OK] AI tool: $ai_tool (found)"
      else
        echo "[!] AI tool: $ai_tool (configured but not found in PATH)"
      fi
    elif command -v "$ai_cmd" >/dev/null 2>&1; then
      echo "[OK] AI tool: $ai_tool (found)"
    else
      echo "[!] AI tool: $ai_tool (configured but not found in PATH)"
    fi
  else
    echo "[i] AI tool: none configured"
  fi

  local os
  os=$(detect_os)
  echo "[OK] Platform: $os"

  echo ""
  if [ "$issues" -eq 0 ]; then
    echo "Everything looks good!"
    return 0
  fi

  echo "[!] Found $issues issue(s)"
  return 1
}
CMD_DOCTOR_STANDALONE

# Add the main invocation at the very end
echo '' >> "$OUTPUT_FILE"
echo '# Run main' >> "$OUTPUT_FILE"
echo 'main "$@"' >> "$OUTPUT_FILE"

# Rebrand user-facing command text across embedded command handlers/help.
python3 - "$OUTPUT_FILE" <<'PY'
from pathlib import Path
import sys

path = Path(sys.argv[1])
text = path.read_text()
had_trailing_newline = text.endswith("\n")
text = text.replace("git gtr", "worktree-cli")
text = text.replace("git-gtr", "worktree-cli")
lines = text.splitlines()
text = "\n".join(line.rstrip(" \t") for line in lines)
if had_trailing_newline:
    text += "\n"
path.write_text(text)
PY

# Make executable
chmod +x "$OUTPUT_FILE"

# Keep a full git-gtr compatibility binary to preserve old update/install paths.
cp "$OUTPUT_FILE" "$SHIM_FILE"
chmod +x "$SHIM_FILE"

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
echo "  Shim: $SHIM_FILE"
echo "  Size: ${lines} lines, ${size} bytes"
echo "  Version: ${VERSION}"
