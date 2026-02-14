#!/usr/bin/env bash
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
YOLO="$(nix build "$SCRIPT_DIR/.." --no-link --print-out-paths 2>/dev/null)/bin/yolo"
PASS=0
FAIL=0

check() {
  local desc="$1"
  shift
  if "$@"; then
    echo "PASS: $desc"
    ((PASS++))
  else
    echo "FAIL: $desc"
    ((FAIL++))
  fi
}

check_output() {
  local desc="$1" expected="$2"
  shift 2
  local actual
  actual="$("$@" 2>&1)"
  if [[ $actual == "$expected" ]]; then
    echo "PASS: $desc"
    ((PASS++))
  else
    echo "FAIL: $desc (expected '$expected', got '$actual')"
    ((FAIL++))
  fi
}

check_contains() {
  local desc="$1" pattern="$2"
  shift 2
  local actual
  actual="$("$@" 2>&1)"
  if echo "$actual" | grep -q "$pattern"; then
    echo "PASS: $desc"
    ((PASS++))
  else
    echo "FAIL: $desc (expected to contain '$pattern', got '$actual')"
    ((FAIL++))
  fi
}

# Basic commands
check_output "echo hello" "hello" "$YOLO" run echo hello
check_output "pwd" "$(pwd)" "$YOLO" run pwd
check_output "whoami" "$(whoami)" "$YOLO" run whoami
check_output "id -u" "$(id -u)" "$YOLO" run id -u
check_output "hostname" "$(hostname)" "$YOLO" run hostname

# Nix store visible
check "nix store visible" test -n "$("$YOLO" run ls /nix/store | head -5)"
check_contains "nix --version" "nix" "$YOLO" run nix --version

# Home is isolated (tmpfs - host dotfiles absent)
check "home is isolated" "$YOLO" run bash -c "! test -e ~/.bashrc && ! test -e ~/.bash_history"

# Project dir is rw
check "project dir rw" "$YOLO" run bash -c "touch testfile-poc && cat testfile-poc && rm testfile-poc"

# /etc/passwd has only root/nobody/current user
line_count="$("$YOLO" run bash -c "wc -l < /etc/passwd" 2>&1)"
check_output "passwd has 3 lines" "3" echo "$line_count"
check_contains "passwd has current user" "$(whoami)" "$YOLO" run cat /etc/passwd

# SSL certs present
check_contains "ssl certs present" "BEGIN CERTIFICATE" "$YOLO" run bash -c "head -5 /etc/ssl/certs/ca-certificates.crt"

# Nix daemon communication
check "nix store info" "$YOLO" run nix store info

# Claude Code available
check "claude binary available" "$YOLO" run bash -c "command -v claude"

# Codex available
check "codex binary available" "$YOLO" run bash -c "command -v codex"

# Gemini CLI available
check "gemini binary available" "$YOLO" run bash -c "command -v gemini"

# Ralphex available
check "ralphex binary available" "$YOLO" run bash -c "command -v ralphex"

# Claude state persistence
test_state_dir="$(mktemp -d)"
export XDG_DATA_HOME="$test_state_dir"
"$YOLO" run bash -c "echo persistence-marker > ~/.claude/marker"
check_output "claude state persists" "persistence-marker" "$YOLO" run cat ~/.claude/marker
rm -rf "$test_state_dir"
unset XDG_DATA_HOME

# Codex state persistence
test_state_dir="$(mktemp -d)"
export XDG_DATA_HOME="$test_state_dir"
"$YOLO" run bash -c "echo codex-marker > ~/.codex/marker"
check_output "codex state persists" "codex-marker" "$YOLO" run cat ~/.codex/marker
rm -rf "$test_state_dir"
unset XDG_DATA_HOME

# Gemini state persistence
test_state_dir="$(mktemp -d)"
export XDG_DATA_HOME="$test_state_dir"
"$YOLO" run bash -c "echo gemini-marker > ~/.gemini/marker"
check_output "gemini state persists" "gemini-marker" "$YOLO" run cat ~/.gemini/marker
rm -rf "$test_state_dir"
unset XDG_DATA_HOME

# Ralphex state persistence
test_state_dir="$(mktemp -d)"
export XDG_DATA_HOME="$test_state_dir"
"$YOLO" run bash -c "mkdir -p ~/.config/ralphex && echo ralphex-marker > ~/.config/ralphex/marker"
check_output "ralphex state persists" "ralphex-marker" "$YOLO" run cat ~/.config/ralphex/marker
rm -rf "$test_state_dir"
unset XDG_DATA_HOME

# gh config persistence
test_state_dir="$(mktemp -d)"
export XDG_DATA_HOME="$test_state_dir"
"$YOLO" run bash -c "echo gh-marker > ~/.config/gh/marker"
check_output "gh config persists" "gh-marker" "$YOLO" run cat ~/.config/gh/marker
rm -rf "$test_state_dir"
unset XDG_DATA_HOME

# Subcommands invoke correct binaries
check_contains "yolo codex runs codex" "codex" "$YOLO" codex --help
check_contains "yolo gemini runs gemini" "gemini" "$YOLO" gemini --help

# Terminfo available
# shellcheck disable=SC2016
check "TERMINFO_DIRS set" "$YOLO" run bash -c 'test -n "$TERMINFO_DIRS"'
# shellcheck disable=SC2016
check "terminfo database exists" "$YOLO" run bash -c 'test -d "$TERMINFO_DIRS"'
# shellcheck disable=SC2016
check "terminfo entry for xterm" "$YOLO" run bash -c 'test -e "$TERMINFO_DIRS/x/xterm"'

# Locale support
# shellcheck disable=SC2016
check "LOCALE_ARCHIVE set" "$YOLO" run bash -c 'test -n "$LOCALE_ARCHIVE"'
# shellcheck disable=SC2016
check_output "LANG is C.UTF-8" "C.UTF-8" "$YOLO" run bash -c 'echo $LANG'
# shellcheck disable=SC2016
check "locale runs without warnings" "$YOLO" run bash -c 'test -z "$(locale 2>&1 >/dev/null)"'

# Base tools available
check "jq available" "$YOLO" run bash -c "command -v jq"
check "rg available" "$YOLO" run bash -c "command -v rg"
check "fd available" "$YOLO" run bash -c "command -v fd"
check "gh available" "$YOLO" run bash -c "command -v gh"
check "make available" "$YOLO" run bash -c "command -v make"
check "ssh available" "$YOLO" run bash -c "command -v ssh"
check "less available" "$YOLO" run bash -c "command -v less"
check "tar available" "$YOLO" run bash -c "command -v tar"

# Exit code propagation
"$YOLO" run false
exit_code=$?
check_output "exit code propagation" "1" echo "$exit_code"

echo ""
echo "Results: $PASS passed, $FAIL failed"
exit "$FAIL"
