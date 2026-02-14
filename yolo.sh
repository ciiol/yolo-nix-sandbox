gen_passwd() {
  local uid gid user
  uid="$(id -u)"
  gid="$(id -g)"
  user="$(id -un)"
  printf 'root:x:0:0:root:/root:/bin/bash\nnobody:x:65534:65534:Nobody:/:/nope\n%s:x:%s:%s:%s:/home/%s:/bin/bash\n' \
    "$user" "$uid" "$gid" "$user" "$user"
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
}

run_sandbox() {
  tmpdir="$(mktemp -d)"
  trap 'rm -rf "$tmpdir"' EXIT

  local etc_dir="$tmpdir/etc"
  mkdir "$etc_dir"
  build_etc "$etc_dir"

  local home_dir="$tmpdir/home"
  mkdir "$home_dir"

  local user home
  user="$(id -un)"
  home="/home/$user"

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

  bwrap \
    --ro-bind /nix/store /nix/store \
    --ro-bind /nix/var/nix/db /nix/var/nix/db \
    --bind /nix/var/nix/daemon-socket /nix/var/nix/daemon-socket \
    --bind "$etc_dir" /etc \
    --bind "$home_dir" "$home" \
    --proc /proc \
    --dev /dev \
    --tmpfs /tmp \
    --bind "$PWD" "$PWD" \
    --bind "$claude_data_dir" "$home/.claude" \
    --bind "$codex_data_dir" "$home/.codex" \
    --bind "$gemini_data_dir" "$home/.gemini" \
    --bind "$ralphex_data_dir" "$home/.config/ralphex" \
    --bind "$gh_data_dir" "$home/.config/gh" \
    --ro-bind "$git_config_dir" "$home/.config/git" \
    --ro-bind "$ssh_config_dir" "$home/.ssh" \
    --bind "$ssh_config_dir/known_hosts" "$home/.ssh/known_hosts" \
    --bind "$ssh_config_dir/allowed_signers" "$home/.ssh/allowed_signers" \
    --clearenv \
    --setenv PATH "@SANDBOX_PROFILE@/bin:@SANDBOX_PROFILE@/sbin" \
    --setenv HOME "$home" \
    --setenv USER "$user" \
    --setenv SHELL "@SANDBOX_PROFILE@/bin/bash" \
    --setenv TERM "xterm-256color" \
    --setenv TERMINFO_DIRS "@SANDBOX_PROFILE@/share/terminfo" \
    --setenv PAGER less \
    --setenv LOCALE_ARCHIVE "@SANDBOX_PROFILE@/lib/locale/locale-archive" \
    --setenv LANG "C.UTF-8" \
    --setenv NIX_REMOTE daemon \
    --unshare-ipc \
    --unshare-pid \
    --unshare-uts \
    --chdir "$PWD" \
    --die-with-parent \
    --new-session \
    -- "$@"
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
