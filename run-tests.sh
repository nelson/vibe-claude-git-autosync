#!/bin/bash

# run-tests.sh - Local test runner with additional options

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

# Make scripts executable
chmod +x git-autosync.sh
chmod +x test-git-autosync.sh

# Run tests
echo "Running git-autosync tests..."
./test-git-autosync.sh ./git-autosync.sh

echo "Running additional validation..."

# Test that script exists and is executable
if [ ! -f "git-autosync" ]; then
    echo "ERROR: git-autosync script not found"
    exit 1
fi

if [ ! -x "git-autosync" ]; then
    echo "ERROR: git-autosync script is not executable"
    exit 1
fi

# Test script behavior outside git repo
temp_dir=$(mktemp -d)
cd "$temp_dir"

if "$SCRIPT_DIR/git-autosync" 2>/dev/null; then
    echo "ERROR: Script should fail when not in git repository"
    exit 1
else
    echo "✓ Script correctly fails when not in git repository"
fi

# Cleanup
rm -rf "$temp_dir"

echo "All validation tests passed!"
