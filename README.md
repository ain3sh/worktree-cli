# worktree-cli

A standalone, single-file distribution of [git-worktree-runner](https://github.com/coderabbitai/git-worktree-runner) — manage git worktrees with ease.

## Install

```bash
curl -fsSL https://ain3sh.com/worktree-cli/install.sh | bash
```
equivalent to:
```bash
curl -fsSL https://raw.githubusercontent.com/ain3sh/worktree-cli/main/scripts/install.sh | bash
```

Or download directly:

```bash
curl -fsSL https://raw.githubusercontent.com/ain3sh/worktree-cli/main/git-gtr -o ~/.local/bin/git-gtr
chmod +x ~/.local/bin/git-gtr
```

**Requirements:** Bash 3.2+, Git 2.5+

## Quick Start

```bash
# One-time setup (in your repo)
git gtr config set gtr.editor.default cursor
git gtr config set gtr.ai.default claude

# Daily workflow
git gtr new my-feature        # Create worktree
git gtr editor my-feature     # Open in editor
git gtr ai my-feature         # Start AI tool
git gtr rm my-feature         # Clean up when done
```

## Commands

| Command | Description |
|---------|-------------|
| `new <branch>` | Create a worktree for a branch |
| `rm <branch>` | Remove a worktree |
| `editor <branch>` | Open worktree in your editor |
| `ai <branch>` | Start AI coding tool in worktree |
| `go <branch>` | Print worktree path (use with `cd "$(git gtr go branch)"`) |
| `run <branch> <cmd>` | Run a command inside the worktree |
| `list` | List all worktrees |
| `config` | Get/set configuration |
| `doctor` | Check your setup |
| `adapter` | List available editor & AI adapters |
| `clean` | Remove stale worktrees |

Use `git gtr help` for full details and options.

### Command Examples

```bash
# Create worktree from a specific branch
git gtr new feature-auth --from develop

# Create parallel worktrees from current branch
git gtr new experiment-1 --from-current
git gtr new experiment-2 --from-current

# Run tests in a worktree
git gtr run feature-auth npm test

# Navigate to a worktree
cd "$(git gtr go feature-auth)"

# Remove worktree and delete the branch
git gtr rm feature-auth --delete-branch

# Open main repo (use '1' as identifier)
git gtr editor 1
```

## Configuration

Configuration is stored via `git config`. Set per-repo (default) or globally with `--global`.

| Key | Description |
|-----|-------------|
| `gtr.editor.default` | Default editor: `cursor`, `vscode`, `zed`, `vim`, `nvim`, `emacs`, `idea`, etc. |
| `gtr.ai.default` | Default AI tool: `claude`, `aider`, `codex`, `continue`, `cursor`, `gemini`, `opencode` |
| `gtr.worktrees.dir` | Custom worktrees directory (default: `../<repo>-worktrees`) |
| `gtr.copy.include` | File patterns to copy to new worktrees (multi-value) |
| `gtr.hook.postCreate` | Commands to run after creating a worktree (multi-value) |

```bash
# Examples
git gtr config set gtr.editor.default vscode
git gtr config set gtr.ai.default aider --global
git gtr config add gtr.copy.include ".env"
git gtr config add gtr.copy.include ".env.local"
git gtr config add gtr.hook.postCreate "npm install"
```

## Alternative Installation

### Manual

1. Download the executable:
   ```bash
   curl -fsSL https://raw.githubusercontent.com/ain3sh/worktree-cli/main/git-gtr -o git-gtr
   chmod +x git-gtr
   ```

2. Move to a directory in your PATH:
   ```bash
   mv git-gtr ~/.local/bin/
   # or system-wide:
   sudo mv git-gtr /usr/local/bin/
   ```

### From Source

```bash
git clone https://github.com/ain3sh/worktree-cli.git
cd YOUR_REPO
.github/scripts/build-standalone.sh
./scripts/install.sh
```

## How It Works

This project packages the multi-file [git-worktree-runner](https://github.com/coderabbitai/git-worktree-runner) into a single portable shell script. All libraries and adapters are bundled inline — no external dependencies beyond Bash and Git.

The build script (`.github/scripts/build-standalone.sh`) clones the upstream repo and merges:
- Core libraries (`lib/*.sh`)
- Editor adapters (Cursor, VS Code, Vim, etc.)
- AI tool adapters (Claude, Aider, etc.)
- Dependency checking with install hints

## License

Apache 2.0 — Same as the original [git-worktree-runner](https://github.com/coderabbitai/git-worktree-runner).
