#!/usr/bin/env bats

load test_helper

@test "mirror.sh: exits when GITPRESERVER_TOKEN is missing" {
    export GITPRESERVER_USERNAME=alice
    run "${REPO_ROOT}/backup/mirror.sh"
    [ "${status}" -ne 0 ]
    [[ "${output}" == *"GITPRESERVER_TOKEN is required"* ]]
}

@test "mirror.sh: exits when GITPRESERVER_USERNAME is missing" {
    export GITPRESERVER_TOKEN=ghp_dummy
    run "${REPO_ROOT}/backup/mirror.sh"
    [ "${status}" -ne 0 ]
    [[ "${output}" == *"GITPRESERVER_USERNAME is required"* ]]
}

@test "mirror.sh: rejects shell metacharacters in username" {
    export GITPRESERVER_TOKEN=ghp_dummy
    export GITPRESERVER_USERNAME='alice;rm -rf /'
    run "${REPO_ROOT}/backup/mirror.sh"
    [ "${status}" -ne 0 ]
    [[ "${output}" == *"invalid characters"* ]]
}

@test "mirror.sh: rejects path traversal in username" {
    export GITPRESERVER_TOKEN=ghp_dummy
    export GITPRESERVER_USERNAME='../etc'
    run "${REPO_ROOT}/backup/mirror.sh"
    [ "${status}" -ne 0 ]
    [[ "${output}" == *"invalid characters"* ]]
}

@test "mirror.sh: rejects unknown host type" {
    export GITPRESERVER_TOKEN=ghp_dummy
    export GITPRESERVER_USERNAME=alice
    export GITPRESERVER_HOST_TYPE=launchpad
    export GITPRESERVER_DRY_RUN=false
    # Place a stub ghorg in PATH so the script gets past binary lookup
    # before hitting the case branch (it won't reach ghorg, but PATH lookup
    # under `set -e` shouldn't fail either way).
    run "${REPO_ROOT}/backup/mirror.sh"
    [ "${status}" -ne 0 ]
    [[ "${output}" == *"unsupported GITPRESERVER_HOST_TYPE"* ]]
}

@test "mirror.sh: gitea host type requires GITPRESERVER_HOST_URL" {
    export GITPRESERVER_TOKEN=ghp_dummy
    export GITPRESERVER_USERNAME=alice
    export GITPRESERVER_HOST_TYPE=gitea
    run "${REPO_ROOT}/backup/mirror.sh"
    [ "${status}" -ne 0 ]
    [[ "${output}" == *"GITPRESERVER_HOST_URL"* ]]
}

@test "mirror.sh: dry-run exits 0 without invoking ghorg" {
    export GITPRESERVER_TOKEN=ghp_dummy
    export GITPRESERVER_USERNAME=alice
    export GITPRESERVER_DRY_RUN=true
    run "${REPO_ROOT}/backup/mirror.sh"
    [ "${status}" -eq 0 ]
    [[ "${output}" == *"DRY RUN"* ]]
}

@test "mirror.sh: accepts dotted usernames like 'my.org'" {
    export GITPRESERVER_TOKEN=ghp_dummy
    export GITPRESERVER_USERNAME='my.org'
    export GITPRESERVER_DRY_RUN=true
    run "${REPO_ROOT}/backup/mirror.sh"
    [ "${status}" -eq 0 ]
}
