# git-autosync

---
model: claude-sonnet-4
created: 2025-07-30
---

## Introduction

git-autosync is a git hook that performs automatic syncing of the repo to upstream.

For copies of the repo that are not modified often, it will ensure that the local copy will always reflect the upstream state.

For copies of the repo that are modified often, it will ensure that local changes are always sent upstream.

## Design

The hook is written in bash with minimal dependencies.

1. If there are any untracked changes, add them to the git repo to be tracked.
2. If there are any tracked changes, stash them.
3. Fetch latest blobs from the upstream named origin.
4. Rebase current HEAD to origin/master. If the rebase fails, return an error and abort.
5. Pop the stash and commit changes. The commit message should summarise the number of files that have been added, changed, and deleted. It should also specify the local hostname that originated the commit.
6. Push the committed changes to origin/master.

## Response

Looking at your spec, I'll create a bash script that implements the git-autosync functionality. This would typically be used as a git hook (like `post-commit` or could be run manually/via cron).I've created a comprehensive bash script that implements your git-autosync specification. Here are the key features:

**Core Functionality:**
- Adds untracked files to git tracking
- Stashes any tracked changes before syncing
- Fetches from origin and rebases to origin/master
- Applies stashed changes and creates a descriptive commit
- Pushes changes back to origin/master

**Error Handling:**
- Exits on errors with proper cleanup
- Validates git repository and origin remote existence
- Handles rebase conflicts gracefully
- Provides clear error messages

**Commit Message Format:**
The commit messages follow the pattern: `git-autosync: X file(s) added, Y file(s) modified, Z file(s) deleted from [hostname]`

**Usage:**
1. Make the script executable: `chmod +x git-autosync`
2. Use as a git hook by placing it in `.git/hooks/` (e.g., as `post-commit`)
3. Or run manually/via cron for periodic syncing

**Safety Features:**
- Validates repository state before making changes
- Uses `set -e` to exit on any command failure
- Provides colored logging for better visibility
- Handles edge cases like missing origin/master branch

The script is self-contained with minimal dependencies (just standard git and bash utilities), making it suitable for most Unix-like environments.
