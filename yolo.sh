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
  local tmpdir
  tmpdir="$(mktemp -d)"
  trap 'rm -rf "$tmpdir"' EXIT

  local etc_dir="$tmpdir/etc"
  mkdir "$etc_dir"
  build_etc "$etc_dir"

  local user home
  user="$(id -un)"
  home="/home/$user"

  exec bwrap \
    --ro-bind /nix/store /nix/store \
    --ro-bind /nix/var/nix/db /nix/var/nix/db \
    --bind /nix/var/nix/daemon-socket /nix/var/nix/daemon-socket \
    --ro-bind "$etc_dir" /etc \
    --proc /proc \
    --dev /dev \
    --tmpfs /tmp \
    --tmpfs "$home" \
    --bind "$PWD" "$PWD" \
    --setenv PATH "@SANDBOX_PROFILE@/bin:@SANDBOX_PROFILE@/sbin" \
    --setenv HOME "$home" \
    --setenv USER "$user" \
    --setenv TERM "${TERM:-xterm}" \
    --setenv LANG "${LANG:-C.UTF-8}" \
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
  echo "Usage: yolo run <cmd> [args...]"
  exit 1
}

if [[ $# -lt 2 ]] || [[ $1 != "run" ]]; then
  usage
fi

shift # remove "run"

run_sandbox "$@"
