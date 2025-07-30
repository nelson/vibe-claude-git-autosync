#!/bin/bash

# git-autosync - Automatic git repository synchronization hook
# Ensures local repository stays in sync with upstream origin/master

set -e  # Exit on any error

# Color codes for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Logging function
log() {
    echo -e "${GREEN}[git-autosync]${NC} $1"
}

error() {
    echo -e "${RED}[git-autosync ERROR]${NC} $1" >&2
}

warn() {
    echo -e "${YELLOW}[git-autosync WARN]${NC} $1"
}

# Check if we're in a git repository
if ! git rev-parse --git-dir > /dev/null 2>&1; then
    error "Not in a git repository"
    exit 1
fi

# Check if origin remote exists
if ! git remote get-url origin > /dev/null 2>&1; then
    error "No 'origin' remote found"
    exit 1
fi

log "Starting git-autosync process..."

# Step 1: Add any untracked files
log "Checking for untracked files..."
untracked_files=$(git ls-files --others --exclude-standard)
if [ -n "$untracked_files" ]; then
    log "Adding untracked files to git..."
    git add .
    log "Untracked files added"
else
    log "No untracked files found"
fi

# Step 2: Stash any tracked changes
log "Checking for tracked changes..."
stash_needed=false
if ! git diff-index --quiet HEAD --; then
    log "Stashing tracked changes..."
    git stash push -m "git-autosync: temporary stash $(date)"
    stash_needed=true
    log "Changes stashed"
else
    log "No tracked changes to stash"
fi

# Step 3: Fetch from origin
log "Fetching from origin..."
if ! git fetch origin; then
    error "Failed to fetch from origin"
    exit 1
fi
log "Fetch completed"

# Step 4: Rebase current HEAD to origin/master
log "Rebasing to origin/master..."
current_branch=$(git branch --show-current)

# Check if origin/master exists
if ! git show-ref --verify --quiet refs/remotes/origin/master; then
    error "origin/master not found. Please ensure the upstream has a master branch."
    exit 1
fi

if ! git rebase origin/master; then
    error "Rebase failed. Manual intervention required."
    # Try to abort the rebase
    git rebase --abort 2>/dev/null || true
    exit 1
fi
log "Rebase completed successfully"

# Step 5: Pop stash and commit changes if there were any
if [ "$stash_needed" = true ]; then
    log "Applying stashed changes..."
    
    # Pop the stash
    if ! git stash pop; then
        error "Failed to pop stash. There may be conflicts that need manual resolution."
        exit 1
    fi
    
    # Check if there are changes to commit after popping stash
    if ! git diff-index --quiet HEAD --; then
        log "Preparing commit message..."
        
        # Get hostname
        hostname=$(hostname)
        
        # Count changes
        added_files=$(git diff --cached --name-only --diff-filter=A | wc -l)
        modified_files=$(git diff --cached --name-only --diff-filter=M | wc -l)
        deleted_files=$(git diff --cached --name-only --diff-filter=D | wc -l)
        
        # If files aren't staged yet, stage them
        if [ $((added_files + modified_files + deleted_files)) -eq 0 ]; then
            git add -A
            added_files=$(git diff --cached --name-only --diff-filter=A | wc -l)
            modified_files=$(git diff --cached --name-only --diff-filter=M | wc -l)
            deleted_files=$(git diff --cached --name-only --diff-filter=D | wc -l)
        fi
        
        # Build commit message
        commit_msg="git-autosync: "
        msg_parts=()
        
        if [ $added_files -gt 0 ]; then
            msg_parts+=("$added_files file(s) added")
        fi
        if [ $modified_files -gt 0 ]; then
            msg_parts+=("$modified_files file(s) modified")
        fi
        if [ $deleted_files -gt 0 ]; then
            msg_parts+=("$deleted_files file(s) deleted")
        fi
        
        # Join message parts
        if [ ${#msg_parts[@]} -gt 0 ]; then
            commit_msg+=$(IFS=', '; echo "${msg_parts[*]}")
        else
            commit_msg+="changes detected"
        fi
        
        commit_msg+=" from $hostname"
        
        log "Committing changes: $commit_msg"
        git commit -m "$commit_msg"
        log "Changes committed"
    else
        log "No changes to commit after applying stash"
    fi
else
    log "No stashed changes to apply"
fi

# Step 6: Push to origin/master
log "Pushing to origin/master..."
if ! git push origin HEAD:master; then
    error "Failed to push to origin/master"
    exit 1
fi
log "Push completed successfully"

log "git-autosync completed successfully!"

# Summary
total_commits=$(git rev-list --count HEAD ^origin/master 2>/dev/null || echo "0")
if [ "$total_commits" -gt 0 ]; then
    log "Synchronized $total_commits commit(s) with upstream"
else
    log "Repository is up to date with upstream"
fi
