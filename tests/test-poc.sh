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
check "nix store ping" "$YOLO" run nix store ping

# Exit code propagation
"$YOLO" run false
exit_code=$?
check_output "exit code propagation" "1" echo "$exit_code"

echo ""
echo "Results: $PASS passed, $FAIL failed"
exit "$FAIL"
