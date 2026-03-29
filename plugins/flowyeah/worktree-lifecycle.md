# Worktree Lifecycle

Shared worktree setup and teardown procedures. Referenced by skills that create worktrees (build, respond).

Each skill handles its own worktree creation (`git worktree add`) and branch logic. This document covers the lifecycle steps that run **after** creation and **before/during** removal.

## Setup (after worktree creation)

Run these steps in order inside the worktree.

### 1. Symlinks

Resolve `worktree.symlinks` from `flowyeah.yml`. For each entry:

```bash
MAIN_WORKTREE=$(git worktree list --porcelain | /usr/bin/head -1 | /usr/bin/sed 's/worktree //')
TARGET="$MAIN_WORKTREE/<path>"

# Skip if target doesn't exist in main checkout
if [ ! -e "$TARGET" ]; then
  echo "Warning: symlink target not found, skipping: <path>"
  continue
fi

# Create parent directories if needed (for nested paths like vendor/bundle)
/bin/mkdir -p "$(/usr/bin/dirname "<path>")"

/bin/ln -s "$TARGET" "<path>"
```

If `worktree.symlinks` is empty or absent, skip.

### 2. Environment

Resolve `worktree.env` from `flowyeah.yml`:

1. For each entry: if value is `auto`, generate a random 8-char URL-safe base64 string (no padding); otherwise use the literal value.
2. **Persist the resolved values** — the calling skill decides where (e.g., `state.md ## Worktree Env` for build, `respond-state.md ## Worktree Env` for respond). Teardown reads from the same location.
3. Export the resolved env vars into the current shell environment.
4. **Append to `.envrc`** in the worktree root — one `export KEY=VALUE` line per resolved env var, inside a delimited block. Mark `.envrc` as `assume-unchanged` so git ignores the modification in this worktree (the file may already be tracked with the project's own direnv config). If `direnv` is on `PATH`, run `direnv allow .` so it activates automatically when the user enters the directory.
5. Run each command in `worktree.setup` sequentially, with the env vars exported. If any setup command fails, **STOP** and report — do not proceed with broken dependencies.

```bash
# Generate env values (for each "auto" entry)
VALUE=$(/usr/bin/head -c 6 /dev/urandom | /usr/bin/base64 | /usr/bin/tr '+/' '-_' | /usr/bin/tr -d '=')

# Export all resolved env vars
export DB_SUFFIX=kM4tQ8hN
export REDIS_DB=pL7nR2wY

# Prevent git from detecting changes to .envrc in this worktree
git update-index --assume-unchanged .envrc 2>/dev/null

# Append flowyeah env vars to .envrc (preserves project's existing direnv config)
/bin/cat >> .envrc <<'ENVRC'

# BEGIN flowyeah
export DB_SUFFIX=kM4tQ8hN
export REDIS_DB=pL7nR2wY
# END flowyeah
ENVRC

# Auto-approve for direnv if available
/usr/bin/which direnv >/dev/null 2>&1 && direnv allow .

# Run setup commands (from worktree.setup)
<setup command 1>
<setup command 2>
```

If `worktree.env` is empty or absent, skip.

### 3. Persist env for teardown

The calling skill **must** write the resolved env key-value pairs to its session state file under a `## Worktree Env` section:

```markdown
## Worktree Env
DB_SUFFIX=kM4tQ8hN
REDIS_DB=pL7nR2wY
```

This section is read during teardown to export the same values before running teardown commands.

## Teardown (before worktree removal)

Run these steps in order. Teardown is **best-effort** — failures warn but don't block removal.

### 1. Close IDE windows

Prevent VSCode from freezing when the worktree directory disappears:

1. Check if `code` CLI is available (`which code`)
2. If available, run `code --status 2>/dev/null` and check if any window lists the worktree path
3. If a window is found, close it: `code "$WORKTREE_PATH" --command "workbench.action.closeWindow"`
4. If `code --status` fails or isn't available, scan `/proc/*/cmdline` for VSCode processes containing the worktree path as a fallback
5. Best-effort — if detection or closing fails, warn and continue

```bash
if /usr/bin/which code >/dev/null 2>&1; then
  code "$WORKTREE_PATH" --command "workbench.action.closeWindow" 2>/dev/null || \
    echo "Warning: Failed to close VSCode window, continuing with cleanup" >&2
fi
```

### 2. Run teardown commands

1. Read env vars from the session state file's `## Worktree Env` section
2. Export them
3. Run each command in `worktree.teardown` from `flowyeah.yml` sequentially
4. Best-effort — if a command fails (e.g., database already dropped), warn and continue

```bash
# Export worktree env
export DB_SUFFIX=kM4tQ8hN
export REDIS_DB=pL7nR2wY

# Run teardown commands (from worktree.teardown)
<teardown command 1>
```

### 3. Remove worktree

```bash
cd "$MAIN_WORKTREE"
git worktree remove <worktree-path>
```

If removal fails (e.g., uncommitted changes), report the error. Do not force-remove without user confirmation.
