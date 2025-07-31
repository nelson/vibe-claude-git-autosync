#!/bin/bash

# test-git-autosync.sh - Test harness for git-autosync script

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

# Test state
TESTS_RUN=0
TESTS_PASSED=0
TESTS_FAILED=0
TEST_DIR=""
TEST_SCRIPT=""

# Logging functions
log() {
    echo -e "${BLUE}[TEST]${NC} $1"
}

success() {
    echo -e "${GREEN}[PASS]${NC} $1"
}

fail() {
    echo -e "${RED}[FAIL]${NC} $1"
}

warn() {
    echo -e "${YELLOW}[WARN]${NC} $1"
}

# Setup test environment
setup_test_env() {
    TEST_DIR=$(mktemp -d)
    log "Test directory: $TEST_DIR"
    cd "$TEST_DIR"
}

# Cleanup test environment
cleanup_test_env() {
    if [ -n "$TEST_DIR" ] && [ -d "$TEST_DIR" ]; then
        rm -rf "$TEST_DIR"
        log "Cleaned up test directory"
    fi
}

# Create a git repository
create_repo() {
    cd "$TEST_DIR"
    local repo_name="$1"
    local is_bare="$2"

    mkdir -p "$repo_name"
    cd "$repo_name"

    if [ "$is_bare" = "true" ]; then
        git init --bare
    else
        git init
        git config user.name "Test User"
        git config user.email "test@example.com"
        # Create initial commit to avoid issues with empty repos
        echo "# $repo_name" > README.md
        git add README.md
        git commit -m "Initial commit"
    fi
}

# Create a commit in a repository
create_commit() {
    cd "$TEST_DIR"
    local repo_name="$1"
    local commit_name="$2"
    local file_content="$3"
    local conflicting="${4:-false}"

    if [ ! -d "$repo_name" ]; then
        fail "Cannot cd: $repo_name does not exist"
        return 1
    fi
    cd "$repo_name"

    if [ "$conflicting" = "true" ]; then
        # Create a file that will conflict
        echo "$file_content" > conflict.txt
        git add conflict.txt
    else
        # Create a unique file for this commit
        echo "$file_content" > "${commit_name}.txt"
        git add "${commit_name}.txt"
    fi

    git commit -m "Commit $commit_name"
}

# Get commit hashes from a repository
get_commits() {
    cd "$TEST_DIR"
    local repo_name="$1"
    if [ ! -d "$repo_name" ]; then
        fail "Cannot cd: $repo_name does not exist"
        return 1
    fi
    cd "$repo_name"
    git log --oneline --format="%H %s"
}

# Compare commit logs
compare_commits() {
    cd "$TEST_DIR"
    local repo_a="$1"
    local repo_b="$2"

    local commits_a=$(get_commits "$repo_a")
    local commits_b=$(get_commits "$repo_b")

    if [ "$commits_a" = "$commits_b" ]; then
        return 0
    else
        return 1
    fi
}

# Run git-autosync in a repository
run_autosync() {
    cd "$TEST_DIR"
    local repo_name="$1"
    local script_path="$2"

    if [ ! -d "$repo_name" ]; then
        fail "Cannot cd: $repo_name does not exist"
        return 1
    fi
    cd "$repo_name"

    # Capture both stdout and stderr, and the exit code
    local output
    local exit_code

    if output=$("$script_path" 2>&1); then
        exit_code=0
    else
        exit_code=$?
        fail "Output from git-autosync:"
        fail "$output"
    fi

    return $exit_code
}

# Test case wrapper
run_test() {
    local test_name="$1"
    local test_function="$2"

    log "Running test: $test_name"
    TESTS_RUN=$((TESTS_RUN + 1))

    # Setup fresh environment for each test
    cleanup_test_env
    setup_test_env

    if $test_function; then
        success "$test_name"
        TESTS_PASSED=$((TESTS_PASSED + 1))
    else
        fail "$test_name"
        TESTS_FAILED=$((TESTS_FAILED + 1))
    fi
}

# Test Case 1: Both repos have same commit
test_case_1() {
    log "Test Case 1: Repo A has commit X. Repo B has commit X. Both should remain with commit X only."

    # Create repo A and push initial state
    create_repo "repo_a" false
    create_commit "repo_a" "X" "Content X"

    # Create repo B (clone from origin)
    cd "$TEST_DIR"
    git clone repo_a repo_b

    # Both repos should have same commits
    local commits_before_a=$(get_commits "repo_a")
    local commits_before_b=$(get_commits "repo_b")

    # Run autosync on repo B
    if run_autosync "repo_b" $TEST_SCRIPT; then
        # Check commits after autosync
        local commits_after_a=$(get_commits "repo_a")
        local commits_after_b=$(get_commits "repo_b")

        # Both repos should still have the same commits
        if [ "$commits_before_a" = "$commits_after_a" ] && [ "$commits_before_b" = "$commits_after_b" ] && compare_commits "repo_a" "repo_b"; then
            return 0
        else
            fail "Commits changed unexpectedly"
            return 1
        fi
    else
        fail "Autosync failed when it should have succeeded"
        return 1
    fi
}

# Test Case 2: Origin has newer commit
test_case_2() {
    log "Test Case 2: Repo A has commits X, Y. Repo B has commit X. Both should end with X, Y."

    # Create repo A
    create_repo "repo_a" false
    create_commit "repo_a" "X" "Content X"

    # Create repo B (clone from origin)
    cd "$TEST_DIR"
    git clone repo_a repo_b

    # Add commit Y to repo A and push
    create_commit "repo_a" "Y" "Content Y"

    # Run autosync on repo B
    if run_autosync "repo_b" $TEST_SCRIPT; then
        # Both repos should now have commits X and Y
        if compare_commits "repo_a" "repo_b"; then
            # Verify we have exactly 3 commits (initial + X + Y)
            local commit_count=$(cd repo_b && git rev-list --count HEAD)
            if [ "$commit_count" = "3" ]; then
                return 0
            else
                fail "Expected 3 commits, got $commit_count"
                return 1
            fi
        else
            fail "Repository commits don't match"
            return 1
        fi
    else
        fail "Autosync failed when it should have succeeded"
        return 1
    fi
}

# Test Case 3: Local repo has newer commit
test_case_3() {
    log "Test Case 3: Repo A has commit X. Repo B has commits X, Y. Both should end with X, Y."

    # Create origin repo (bare)
    create_repo "origin.git" true

    # Create repo A
    create_repo "repo_a" false
    git remote add origin "../origin.git"
    create_commit "repo_a" "X" "Content X"
    git push origin master

    # Create repo B (clone from origin)
    cd "$TEST_DIR"
    git clone origin.git repo_b
    cd repo_b
    git config user.name "Test User"
    git config user.email "test@example.com"
    create_commit "repo_b" "Y" "Content Y"

    # Run autosync on repo B
    if run_autosync "repo_b" $TEST_SCRIPT; then
        # Both repos should now have commits X and Y
        if compare_commits "origin.git" "repo_b"; then
            # Verify we have exactly 3 commits (initial + X + Y)
            local commit_count=$(cd repo_b && git rev-list --count HEAD)
            if [ "$commit_count" = "3" ]; then
                return 0
            else
                fail "Expected 3 commits, got $commit_count"
                return 1
            fi
        else
            fail "Repository commits don't match"
            return 1
        fi
    else
        fail "Autosync failed when it should have succeeded"
        return 1
    fi
}

# Test Case 4: Non-conflicting divergent commits
test_case_4() {
    log "Test Case 4: Repo A has X, Y. Repo B has X, Z. Non-conflicting changes should result in X, Y, Z'."

    # Create origin repo (bare)
    create_repo "origin.git" true

    # Create repo A
    create_repo "repo_a" false
    git remote add origin "../origin.git"
    create_commit "repo_a" "X" "Content X"
    git push origin master

    # Create repo B (clone from origin)
    cd "$TEST_DIR"
    git clone origin.git repo_b
    cd repo_b
    git config user.name "Test User"
    git config user.email "test@example.com"

    # Add commit Y to repo A (different file)
    create_commit "repo_a" "Y" "Content Y"
    git push origin master

    # Add commit Z to repo B (different file, non-conflicting)
    create_commit "repo_b" "Z" "Content Z"

    # Run autosync on repo B
    if run_autosync "repo_b" $TEST_SCRIPT; then

        # Both repos should now have commits X, Y, and Z (rebased)
        if compare_commits "origin.git" "repo_b"; then
            # Verify we have exactly 4 commits (initial + X + Y + Z)
            local commit_count=$(cd repo_b && git rev-list --count HEAD)
            if [ "$commit_count" = "4" ]; then
                # Verify that both Y and Z changes are present
                if [ -f "repo_b/Y.txt" ] && [ -f "repo_b/Z.txt" ]; then
                    return 0
                else
                    fail "Expected files from both commits not found"
                    return 1
                fi
            else
                fail "Expected 4 commits, got $commit_count"
                return 1
            fi
        else
            fail "Repository commits don't match"
            return 1
        fi
    else
        fail "Autosync failed when it should have succeeded"
        return 1
    fi
}

# Test Case 5: Conflicting divergent commits
test_case_5() {
    log "Test Case 5: Repo A has X, Y. Repo B has X, Z. Conflicting changes should fail and leave repos unmodified."

    # Create origin repo (bare)
    create_repo "origin.git" true

    # Create repo A
    create_repo "repo_a" false
    git remote add origin "../origin.git"
    create_commit "repo_a" "X" "Content X"
    git push origin master

    # Create repo B (clone from origin)
    cd "$TEST_DIR"
    git clone origin.git repo_b
    cd repo_b
    git config user.name "Test User"
    git config user.email "test@example.com"

    # Add conflicting commit Y to repo A
    create_commit "repo_a" "Y" "Content Y from A" true
    git push origin master

    # Add conflicting commit Z to repo B (same file, different content)
    create_commit "repo_b" "Z" "Content Z from B" true

    # Store commits before autosync
    local commits_before_a=$(get_commits "origin.git")
    local commits_before_b=$(get_commits "repo_b")

    # Run autosync on repo B - should fail
    if run_autosync "repo_b" $TEST_SCRIPT; then
        fail "Autosync succeeded when it should have failed due to conflicts"
        return 1
    else
        # Verify repos are unmodified
        local commits_after_a=$(get_commits "origin.git")
        local commits_after_b=$(get_commits "repo_b")

        if [ "$commits_before_a" = "$commits_after_a" ] && [ "$commits_before_b" = "$commits_after_b" ]; then
            return 0
        else
            fail "Repositories were modified despite conflict"
            return 1
        fi
    fi
}

# Main test runner
main() {
    local script_path="${1:-./git-autosync}"

    if [ ! -f "$script_path" ]; then
        fail "git-autosync script not found at: $script_path"
        exit 1
    fi

    if [ ! -x "$script_path" ]; then
        fail "git-autosync script is not executable: $script_path"
        exit 1
    fi

    # Make script path absolute
    TEST_SCRIPT=$(realpath "$script_path")

    log "Starting git-autosync test suite"
    log "Script path: $TEST_SCRIPT"

    # Trap to ensure cleanup
    trap cleanup_test_env EXIT

    # Run all test cases
    run_test "Same commits in both repos" test_case_1
    run_test "Origin has newer commits" test_case_2
    run_test "Local has newer commits" test_case_3
    run_test "Non-conflicting divergent commits" test_case_4
    run_test "Conflicting divergent commits" test_case_5

    # Print summary
    echo
    log "Test Summary:"
    log "Tests run: $TESTS_RUN"
    success "Tests passed: $TESTS_PASSED"
    fail "Tests failed: $TESTS_FAILED"

    if [ $TESTS_FAILED -eq 0 ]; then
        success "All tests passed!"
        exit 0
    else
        fail "Some tests failed!"
        exit 1
    fi
}

# Run main function with all arguments
main "$@"
