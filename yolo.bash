gen_passwd() {
  local uid gid user
  uid="$(id -u)"
  gid="$(id -g)"
  user="$(id -un)"
  printf 'root:x:0:0:root:/root:/bin/bash\nnobody:x:65534:65534:Nobody:/:/nope\n%s:x:%s:%s:%s:%s:/bin/bash\n' \
    "$user" "$uid" "$gid" "$user" "$HOME"
}

gen_group() {
  local gid group
  gid="$(id -g)"
  group="$(id -gn)"
  printf 'root:x:0:\nnobody:x:65534:\n%s:x:%s:\n' "$group" "$gid"
}

gen_hosts() {
  printf '127.0.0.1 localhost\n::1 localhost\n'
}

build_etc() {
  local etc_dir="$1"
  # Copy sandboxEtc symlinks (they point into /nix/store, so cp -a preserves them)
  # Copy etc as symlinks; ignore broken symlinks and special files
  cp -a "@SANDBOX_ETC@/etc/." "$etc_dir/" 2>/dev/null || true
  chmod -R u+w "$etc_dir"
  # Override with runtime-generated files (remove symlinks first)
  rm -f "$etc_dir/passwd" "$etc_dir/group" "$etc_dir/hosts" "$etc_dir/resolv.conf"
  gen_passwd >"$etc_dir/passwd"
  gen_group >"$etc_dir/group"
  gen_hosts >"$etc_dir/hosts"
  # Use host resolv.conf for DNS
  cp /etc/resolv.conf "$etc_dir/resolv.conf"
  rm -f "$etc_dir/subuid" "$etc_dir/subgid"
}

get_subid_range() {
  local file="$1" user="$2"
  local line start count range
  while IFS=: read -r line start count; do
    if [[ $line == "$user" ]]; then
      range="$start:$count"
    fi
  done <"$file"
  if [[ -z $range ]]; then
    return 1
  fi
  echo "$range"
  return 0
}

has_wide_uid_support() {
  local user uid gid sub_uid_range sub_gid_range

  user="$(id -un)"
  uid="$(id -u)"
  gid="$(id -g)"

  [[ -f /etc/subuid ]] && [[ -f /etc/subgid ]] || return 1

  command -v newuidmap >/dev/null || return 1
  command -v newgidmap >/dev/null || return 1

  sub_uid_range="$(get_subid_range /etc/subuid "$user")" || return 1
  sub_gid_range="$(get_subid_range /etc/subgid "$user")" || return 1

  # The three-range mapping and subuid generation require uid >= 2 and gid >= 2
  # (uid=0 produces a zero-count first mapping; uid=1 produces a zero-count subuid entry)
  local sub_uid_count="${sub_uid_range#*:}"
  local sub_gid_count="${sub_gid_range#*:}"
  if ((uid < 2 || gid < 2 || uid >= sub_uid_count || gid >= sub_gid_count)); then
    return 1
  fi

  WIDE_UID_SUB_UID_RANGE="$sub_uid_range"
  WIDE_UID_SUB_GID_RANGE="$sub_gid_range"
  return 0
}

run_bwrap_wide_uid() {
  local uid gid
  uid="$(id -u)"
  gid="$(id -g)"

  local uid_start uid_count gid_start gid_count
  uid_start="${WIDE_UID_SUB_UID_RANGE%%:*}"
  uid_count="${WIDE_UID_SUB_UID_RANGE#*:}"
  gid_start="${WIDE_UID_SUB_GID_RANGE%%:*}"
  gid_count="${WIDE_UID_SUB_GID_RANGE#*:}"

  # Create FIFOs inside tmpdir so the EXIT trap cleans them up on interrupt
  local fifo_dir="$tmpdir/bwrap-fifos"
  mkdir "$fifo_dir"

  local info_fifo="$fifo_dir/info"
  local block_fifo="$fifo_dir/block"
  mkfifo "$info_fifo" "$block_fifo"

  # Open block_fifo read-write (doesn't block, unlike write-only on FIFOs)
  # so the child's read-open (4<block_fifo) sees a writer and doesn't block
  local block_fd
  exec {block_fd}<>"$block_fifo"

  # --info-fd: bwrap writes {"child-pid": N} JSON to FD 3
  # --userns-block-fd: bwrap reads from FD 4 and blocks until data arrives
  "${BWRAP_CMD[@]}" --info-fd 3 --userns-block-fd 4 "$@" \
    3>"$info_fifo" 4<"$block_fifo" &
  local bwrap_pid=$!

  # Read child PID from info-fd JSON (format: {"child-pid": N, ...})
  local info_json child_pid
  info_json=$(cat "$info_fifo")
  child_pid="${info_json##*\"child-pid\":}"
  child_pid="${child_pid#"${child_pid%%[0-9]*}"}"
  child_pid="${child_pid%%[^0-9]*}"

  if [[ -z $child_pid || ! $child_pid =~ ^[0-9]+$ ]]; then
    echo "yolo: failed to parse child PID from bwrap info: $info_json" >&2
    exec {block_fd}>&-
    kill "$bwrap_pid" 2>/dev/null || true
    wait "$bwrap_pid" 2>/dev/null || true
    return 1
  fi

  # Map UIDs: subordinate range before real uid, real uid, subordinate range after
  if ! newuidmap "$child_pid" \
    0 "$uid_start" "$uid" \
    "$uid" "$uid" 1 \
    $((uid + 1)) $((uid_start + uid)) $((uid_count - uid)); then
    echo "yolo: newuidmap failed" >&2
    exec {block_fd}>&-
    kill "$bwrap_pid" 2>/dev/null || true
    wait "$bwrap_pid" 2>/dev/null || true
    return 1
  fi

  if ! newgidmap "$child_pid" \
    0 "$gid_start" "$gid" \
    "$gid" "$gid" 1 \
    $((gid + 1)) $((gid_start + gid)) $((gid_count - gid)); then
    echo "yolo: newgidmap failed" >&2
    exec {block_fd}>&-
    kill "$bwrap_pid" 2>/dev/null || true
    wait "$bwrap_pid" 2>/dev/null || true
    return 1
  fi

  # Unblock bwrap by writing to the block fd, then close it
  echo >&"$block_fd"
  exec {block_fd}>&-

  wait "$bwrap_pid"
}

run_sandbox() {
  tmpdir="$(mktemp -d)"
  trap 'chmod -R u+rwx "$tmpdir" || true; rm -rf "$tmpdir"' EXIT

  local etc_dir="$tmpdir/etc"
  mkdir "$etc_dir"
  build_etc "$etc_dir"

  local home_dir="$tmpdir/home"
  mkdir "$home_dir"

  local user uid gid
  user="$(id -un)"
  uid="$(id -u)"
  gid="$(id -g)"

  local data_dir="${XDG_DATA_HOME:-$HOME/.local/share}/yolo"

  local git_config_dir="$data_dir/git"
  mkdir -p "$git_config_dir"

  local ssh_config_dir="$data_dir/ssh"
  mkdir -p "$ssh_config_dir"
  touch "$ssh_config_dir/known_hosts"
  touch "$ssh_config_dir/allowed_signers"

  local claude_data_dir="$data_dir/claude"
  mkdir -p "$claude_data_dir"
  touch "$claude_data_dir/.claude.json"
  ln -s .claude/.claude.json "$home_dir/.claude.json"

  local codex_data_dir="$data_dir/codex"
  mkdir -p "$codex_data_dir"

  local gemini_data_dir="$data_dir/gemini"
  mkdir -p "$gemini_data_dir"

  local ralphex_data_dir="$data_dir/ralphex"
  mkdir -p "$ralphex_data_dir"

  local gh_data_dir="$data_dir/gh"
  mkdir -p "$gh_data_dir"

  local containers_data_dir="$data_dir/containers"
  mkdir -p "$containers_data_dir"

  local xdg_runtime_dir="/run/user/$uid"

  local entrypoint_args=()
  if [[ ${DIRENV_DIR:-} == "-$PWD" ]] && [[ -f "$PWD/.envrc" ]]; then
    local allowed
    allowed=$(direnv status --json 2>/dev/null | jq -r '.state.foundRC.allowed // empty') || allowed=""
    if [[ $allowed == "0" ]]; then
      entrypoint_args=(--direnv)
    fi
  fi

  local wide_uid=false
  if has_wide_uid_support; then
    wide_uid=true
    local sub_uid_count sub_gid_count
    sub_uid_count="${WIDE_UID_SUB_UID_RANGE#*:}"
    sub_gid_count="${WIDE_UID_SUB_GID_RANGE#*:}"

    # Generate /etc/subuid and /etc/subgid so podman sees subordinate ranges
    # Split around the real uid/gid: [1..uid) and [uid+1..sub_count)
    # UID/GID 0 is excluded because the kernel rejects nested uid_map writes
    # that reference parent-namespace UID 0 (verify_root_map check)
    printf '%s:1:%s\n%s:%s:%s\n' \
      "$user" "$((uid - 1))" \
      "$user" "$((uid + 1))" "$((sub_uid_count - uid))" \
      >"$etc_dir/subuid"
    printf '%s:1:%s\n%s:%s:%s\n' \
      "$user" "$((gid - 1))" \
      "$user" "$((gid + 1))" "$((sub_gid_count - gid))" \
      >"$etc_dir/subgid"
  fi

  local optional_mounts=()
  if [[ -d /sys/fs/cgroup ]]; then
    optional_mounts+=(--ro-bind /sys/fs/cgroup /sys/fs/cgroup)
  fi
  if [[ -e /dev/net/tun ]]; then
    optional_mounts+=(--dev-bind /dev/net/tun /dev/net/tun)
  fi
  if [[ -d /run/wrappers ]]; then
    optional_mounts+=(--ro-bind /run/wrappers /run/wrappers)
  fi

  local bwrap_args=(
    --ro-bind /nix/store /nix/store
    --ro-bind /nix/var/nix/db /nix/var/nix/db
    --bind /nix/var/nix/daemon-socket /nix/var/nix/daemon-socket
    --ro-bind @SANDBOX_PROFILE@ /run/current-system/sw
    --bind "$etc_dir" /etc
    --bind "$home_dir" "$HOME"
    --proc /proc
    --dev /dev
    "${optional_mounts[@]}"
    --tmpfs /tmp
    --tmpfs /var/tmp
    --bind "$PWD" "$PWD"
    --bind "$claude_data_dir" "$HOME/.claude"
    --bind "$codex_data_dir" "$HOME/.codex"
    --bind "$gemini_data_dir" "$HOME/.gemini"
    --bind "$ralphex_data_dir" "$HOME/.config/ralphex"
    --bind "$gh_data_dir" "$HOME/.config/gh"
    --bind "$containers_data_dir" "$HOME/.local/share/containers"
    --ro-bind "$git_config_dir" "$HOME/.config/git"
    --ro-bind "$ssh_config_dir" "$HOME/.ssh"
    --bind "$ssh_config_dir/known_hosts" "$HOME/.ssh/known_hosts"
    --bind "$ssh_config_dir/allowed_signers" "$HOME/.ssh/allowed_signers"
    --dir "$xdg_runtime_dir"
    --clearenv
    --setenv HOME "$HOME"
    --setenv USER "$user"
    --setenv XDG_RUNTIME_DIR "$xdg_runtime_dir"
  )

  bwrap_args+=(--setenv TERM "$TERM")
  [[ -n ${COLORTERM:-} ]] && bwrap_args+=(--setenv COLORTERM "$COLORTERM")
  [[ -n ${TERM_PROGRAM:-} ]] && bwrap_args+=(--setenv TERM_PROGRAM "$TERM_PROGRAM")
  [[ -n ${TERM_PROGRAM_VERSION:-} ]] && bwrap_args+=(--setenv TERM_PROGRAM_VERSION "$TERM_PROGRAM_VERSION")

  bwrap_args+=(
    --unshare-ipc
    --unshare-pid
    --unshare-uts
    --chdir "$PWD"
    --die-with-parent
  )

  BWRAP_CMD=(setpriv --ambient-caps -all -- bwrap)

  if [[ $wide_uid == true ]]; then
    bwrap_args+=(--unshare-user --cap-add CAP_SETUID --cap-add CAP_SETGID)
    run_bwrap_wide_uid "${bwrap_args[@]}" \
      -- @SANDBOX_ENTRYPOINT@/bin/sandbox-entrypoint "${entrypoint_args[@]}" "$@"
  else
    "${BWRAP_CMD[@]}" "${bwrap_args[@]}" \
      -- @SANDBOX_ENTRYPOINT@/bin/sandbox-entrypoint "${entrypoint_args[@]}" "$@"
  fi
}

usage() {
  echo "Usage: yolo <run|claude|codex|gemini|ralphex> [args...]"
  exit 1
}

if [[ $# -lt 1 ]]; then
  usage
fi

cmd="$1"
shift

case "$cmd" in
run)
  if [[ $# -lt 1 ]]; then
    usage
  fi
  run_sandbox "$@"
  ;;
claude)
  run_sandbox claude --dangerously-skip-permissions "$@"
  ;;
codex)
  run_sandbox codex --yolo "$@"
  ;;
gemini)
  run_sandbox gemini --yolo "$@"
  ;;
ralphex)
  run_sandbox ralphex "$@"
  ;;
*)
  usage
  ;;
esac
