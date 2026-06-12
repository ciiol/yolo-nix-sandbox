use std::env;
use std::fs;
use std::os::unix::fs::PermissionsExt;
use std::path::{Path, PathBuf};
use std::process::{ExitStatus, Stdio};

use anyhow::{Context, Result};
use nix::unistd::{Uid, User, getgid, getuid};

use crate::bwrap;
use crate::etc;
use crate::uid;

fn parse_required_env_path(name: &str, value: Option<String>) -> Result<PathBuf> {
    let val = value.ok_or_else(|| anyhow::anyhow!("{name} env var is not set"))?;
    if val.is_empty() {
        anyhow::bail!("{name} env var is empty");
    }
    Ok(PathBuf::from(val))
}

fn sandbox_env_path(name: &str) -> Result<PathBuf> {
    parse_required_env_path(name, env::var(name).ok())
}

fn parse_optional_env_path(value: Option<String>) -> Option<PathBuf> {
    value.filter(|v| !v.is_empty()).map(PathBuf::from)
}

fn sandbox_env_path_optional(name: &str) -> Option<PathBuf> {
    parse_optional_env_path(env::var(name).ok())
}

/// RAII temp directory matching the bash EXIT trap: chmod -R u+rwx then rm -rf.
/// bwrap may create files with restricted permissions inside the sandbox,
/// so we must fix permissions before removal.
struct SandboxTempDir {
    path: PathBuf,
}

impl SandboxTempDir {
    fn new() -> Result<Self> {
        let path = tempfile::tempdir()
            .context("failed to create temp directory")?
            .keep();
        Ok(Self { path })
    }

    fn path(&self) -> &Path {
        &self.path
    }
}

fn chmod_recursive_writable(path: &Path) {
    let Ok(metadata) = fs::symlink_metadata(path) else {
        return;
    };
    if metadata.is_symlink() {
        return;
    }
    let _ = fs::set_permissions(
        path,
        fs::Permissions::from_mode(metadata.permissions().mode() | 0o700),
    );
    if metadata.is_dir() {
        if let Ok(entries) = fs::read_dir(path) {
            for entry in entries.flatten() {
                chmod_recursive_writable(&entry.path());
            }
        }
    }
}

impl Drop for SandboxTempDir {
    fn drop(&mut self) {
        chmod_recursive_writable(&self.path);
        let _ = fs::remove_dir_all(&self.path);
    }
}

/// Generate /etc/subuid or /etc/subgid content for wide-UID mode.
/// Splits around the real id: [1..id) and [id+1..count)
/// ID 0 is excluded (kernel rejects nested uid_map writes referencing parent-namespace UID 0).
/// Requires id >= 2 and count > id (enforced by is_valid_wide_uid).
fn gen_subid_content(user: &str, id: u32, count: u32) -> String {
    debug_assert!(id >= 2, "gen_subid_content requires id >= 2, got {id}");
    debug_assert!(
        count > id,
        "gen_subid_content requires count > id, got count={count}, id={id}"
    );
    format!("{user}:1:{}\n{user}:{}:{}\n", id - 1, id + 1, count - id,)
}

fn detect_direnv(pwd: &Path) -> bool {
    let direnv_dir = match env::var("DIRENV_DIR") {
        Ok(v) => v,
        Err(_) => return false,
    };

    if direnv_dir != format!("-{}", pwd.display()) {
        return false;
    }

    if !pwd.join(".envrc").is_file() {
        return false;
    }

    let output = match std::process::Command::new("direnv")
        .args(["status", "--json"])
        .stderr(Stdio::null())
        .output()
    {
        Ok(o) => o,
        Err(_) => return false,
    };

    if !output.status.success() {
        return false;
    }

    let json: serde_json::Value = match serde_json::from_slice(&output.stdout) {
        Ok(v) => v,
        Err(_) => return false,
    };

    json.pointer("/state/foundRC/allowed")
        .and_then(|v| v.as_i64())
        .is_some_and(|v| v == 0)
}

enum MountType {
    RoBind,
    DevBind,
}

fn detect_optional_mounts() -> Vec<(MountType, &'static str)> {
    let mut mounts = Vec::new();
    if Path::new("/sys/fs/cgroup").is_dir() {
        mounts.push((MountType::RoBind, "/sys/fs/cgroup"));
    }
    if Path::new("/dev/net/tun").exists() {
        mounts.push((MountType::DevBind, "/dev/net/tun"));
    }
    mounts
}

fn collect_terminal_vars() -> Vec<(String, String)> {
    let mut vars = Vec::new();
    for key in ["TERM", "COLORTERM", "TERM_PROGRAM", "TERM_PROGRAM_VERSION"] {
        if let Ok(val) = env::var(key) {
            if !val.is_empty() {
                vars.push((key.into(), val));
            }
        }
    }
    if let Ok(raw) = env::var("TERMINFO_DIRS") {
        if let Some(resolved) = resolve_host_terminfo_dirs(&raw) {
            vars.push(("YOLO_HOST_TERMINFO_DIRS".into(), resolved));
        }
    }
    vars
}

/// Resolves a colon-separated list of terminfo directories to their canonical
/// `/nix/store` paths. Entries that fail to canonicalize (broken symlinks,
/// missing dirs) are silently skipped. Duplicate canonical targets are kept
/// only once, in first-seen order. Returns `None` if no entries survive.
///
/// The result is intended to be passed into the sandbox under
/// `YOLO_HOST_TERMINFO_DIRS` and merged back into `TERMINFO_DIRS` from
/// `environment.extraInit` (a raw `TERMINFO_DIRS` setenv would be clobbered
/// by `/etc/set-environment`).
fn resolve_host_terminfo_dirs(raw: &str) -> Option<String> {
    let mut seen = std::collections::BTreeSet::new();
    let mut out = Vec::new();
    for entry in raw.split(':').filter(|s| !s.is_empty()) {
        if let Ok(canonical) = std::fs::canonicalize(entry) {
            let s = canonical.to_string_lossy().into_owned();
            if seen.insert(s.clone()) {
                out.push(s);
            }
        }
    }
    if out.is_empty() {
        None
    } else {
        Some(out.join(":"))
    }
}

/// Parameters for bwrap argument construction, extracted for testability.
struct SandboxContext {
    user: String,
    uid: u32,
    home: String,
    pwd: PathBuf,
    etc_dir: PathBuf,
    home_dir: PathBuf,
    data_dir: PathBuf,
    profile: PathBuf,
    entrypoint: PathBuf,
    usrbinenv: Option<PathBuf>,
}

fn build_bwrap_args(
    ctx: &SandboxContext,
    optional_mounts: &[(MountType, &str)],
    terminal_vars: &[(String, String)],
    wide_uid: bool,
    use_direnv: bool,
    command: &[String],
) -> Vec<String> {
    let home = &ctx.home;
    let pwd = ctx.pwd.display().to_string();
    let xdg_runtime_dir = format!("/run/user/{}", ctx.uid);
    let data = &ctx.data_dir;
    let ssh = data.join("ssh");

    let mut args: Vec<String> = Vec::new();

    args.extend([
        "--ro-bind".into(),
        "/nix/store".into(),
        "/nix/store".into(),
        "--ro-bind".into(),
        "/nix/var/nix/db".into(),
        "/nix/var/nix/db".into(),
        "--bind".into(),
        "/nix/var/nix/daemon-socket".into(),
        "/nix/var/nix/daemon-socket".into(),
        "--ro-bind".into(),
        ctx.profile.display().to_string(),
        "/run/current-system/sw".into(),
        "--bind".into(),
        ctx.etc_dir.display().to_string(),
        "/etc".into(),
        "--bind".into(),
        ctx.home_dir.display().to_string(),
        home.clone(),
        "--proc".into(),
        "/proc".into(),
        "--dev".into(),
        "/dev".into(),
    ]);

    for (mount_type, path) in optional_mounts {
        let flag = match mount_type {
            MountType::RoBind => "--ro-bind",
            MountType::DevBind => "--dev-bind",
        };
        args.extend([flag.into(), (*path).into(), (*path).into()]);
    }

    args.extend([
        "--tmpfs".into(),
        "/tmp".into(),
        "--tmpfs".into(),
        "/var/tmp".into(),
        "--bind".into(),
        pwd.clone(),
        pwd,
    ]);

    for (subdir, target) in [
        ("claude", format!("{home}/.claude")),
        ("codex", format!("{home}/.codex")),
        ("pi", format!("{home}/.pi")),
        ("ralphex", format!("{home}/.config/ralphex")),
        ("gh", format!("{home}/.config/gh")),
        ("revdiff", format!("{home}/.config/revdiff")),
        ("sops-age", format!("{home}/.config/sops/age")),
        ("containers", format!("{home}/.local/share/containers")),
    ] {
        args.extend([
            "--bind".into(),
            data.join(subdir).display().to_string(),
            target,
        ]);
    }

    args.extend([
        "--ro-bind".into(),
        data.join("git").display().to_string(),
        format!("{home}/.config/git"),
        "--ro-bind".into(),
        data.join("ssh").display().to_string(),
        format!("{home}/.ssh"),
    ]);

    args.extend([
        "--bind".into(),
        ssh.join("known_hosts").display().to_string(),
        format!("{home}/.ssh/known_hosts"),
        "--bind".into(),
        ssh.join("allowed_signers").display().to_string(),
        format!("{home}/.ssh/allowed_signers"),
    ]);

    args.extend(["--dir".into(), xdg_runtime_dir.clone()]);

    args.extend([
        "--clearenv".into(),
        "--setenv".into(),
        "HOME".into(),
        home.clone(),
        "--setenv".into(),
        "USER".into(),
        ctx.user.clone(),
        "--setenv".into(),
        "XDG_RUNTIME_DIR".into(),
        xdg_runtime_dir,
    ]);

    for (key, val) in terminal_vars {
        args.extend(["--setenv".into(), key.clone(), val.clone()]);
    }

    args.extend([
        "--unshare-ipc".into(),
        "--unshare-pid".into(),
        "--unshare-uts".into(),
        "--chdir".into(),
        ctx.pwd.display().to_string(),
        "--die-with-parent".into(),
    ]);

    if wide_uid {
        args.extend([
            "--unshare-user".into(),
            "--cap-add".into(),
            "CAP_SETUID".into(),
            "--cap-add".into(),
            "CAP_SETGID".into(),
        ]);
    }

    if let Some(path) = &ctx.usrbinenv {
        args.extend([
            "--symlink".into(),
            path.display().to_string(),
            "/usr/bin/env".into(),
        ]);
    }

    args.push("--".into());
    args.push(ctx.entrypoint.display().to_string());
    if use_direnv {
        args.push("--direnv".into());
    }
    args.extend(command.iter().cloned());

    args
}

pub fn run(command: Vec<String>) -> Result<ExitStatus> {
    let profile = sandbox_env_path("SANDBOX_PROFILE")?;
    let etc_source = sandbox_env_path("SANDBOX_ETC")?;
    let entrypoint = sandbox_env_path("SANDBOX_ENTRYPOINT")?;

    let uid = getuid().as_raw();
    let gid = getgid().as_raw();
    let user = User::from_uid(Uid::from_raw(uid))
        .context("failed to look up current user")?
        .context("current user not found")?;
    let home = env::var("HOME").context("HOME not set")?;
    let pwd = env::current_dir().context("failed to get current directory")?;

    let tmpdir = SandboxTempDir::new()?;

    let etc_dir = tmpdir.path().join("etc");
    fs::create_dir(&etc_dir).context("failed to create etc dir")?;
    etc::build_etc(&etc_dir, &etc_source)?;

    let home_dir = tmpdir.path().join("home");
    fs::create_dir(&home_dir).context("failed to create home dir")?;

    let data_dir = env::var("XDG_DATA_HOME")
        .ok()
        .filter(|v| !v.is_empty())
        .map(PathBuf::from)
        .unwrap_or_else(|| PathBuf::from(&home).join(".local/share"))
        .join("yolo");

    for subdir in [
        "claude",
        "codex",
        "pi",
        "ralphex",
        "gh",
        "revdiff",
        "sops-age",
        "containers",
        "git",
        "ssh",
    ] {
        fs::create_dir_all(data_dir.join(subdir))
            .with_context(|| format!("failed to create data dir: {subdir}"))?;
    }

    let ssh_dir = data_dir.join("ssh");
    for name in ["known_hosts", "allowed_signers"] {
        let path = ssh_dir.join(name);
        if !path.exists() {
            fs::write(&path, "").with_context(|| format!("failed to touch {name}"))?;
        }
    }

    let claude_json = data_dir.join("claude/.claude.json");
    if !claude_json.exists() {
        fs::write(&claude_json, "").context("failed to touch .claude.json")?;
    }
    std::os::unix::fs::symlink(".claude/.claude.json", home_dir.join(".claude.json"))
        .context("failed to create .claude.json symlink")?;

    let use_direnv = detect_direnv(&pwd);
    let wide_uid_config = uid::detect_wide_uid_support();

    if let Some(ref config) = wide_uid_config {
        fs::write(
            etc_dir.join("subuid"),
            gen_subid_content(&user.name, uid, config.uid_range.count),
        )
        .context("failed to write subuid")?;
        fs::write(
            etc_dir.join("subgid"),
            gen_subid_content(&user.name, gid, config.gid_range.count),
        )
        .context("failed to write subgid")?;
    }

    let optional_mounts = detect_optional_mounts();
    let terminal_vars = collect_terminal_vars();
    let usrbinenv = sandbox_env_path_optional("SANDBOX_USRBINENV");

    let ctx = SandboxContext {
        user: user.name,
        uid,
        home,
        pwd,
        etc_dir,
        home_dir,
        data_dir,
        profile,
        entrypoint,
        usrbinenv,
    };

    let bwrap_args = build_bwrap_args(
        &ctx,
        &optional_mounts,
        &terminal_vars,
        wide_uid_config.is_some(),
        use_direnv,
        &command,
    );

    if let Some(ref config) = wide_uid_config {
        bwrap::run_wide_uid(&bwrap_args, config, tmpdir.path())
    } else {
        bwrap::run_simple(&bwrap_args)
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    fn test_ctx() -> SandboxContext {
        SandboxContext {
            user: "testuser".into(),
            uid: 1000,
            home: "/home/testuser".into(),
            pwd: PathBuf::from("/home/testuser/project"),
            etc_dir: PathBuf::from("/tmp/sandbox/etc"),
            home_dir: PathBuf::from("/tmp/sandbox/home"),
            data_dir: PathBuf::from("/tmp/sandbox/data"),
            profile: PathBuf::from("/nix/store/fake-profile"),
            entrypoint: PathBuf::from("/nix/store/fake-entrypoint/bin/sandbox-entrypoint"),
            usrbinenv: None,
        }
    }

    fn default_args(ctx: &SandboxContext) -> Vec<String> {
        build_bwrap_args(ctx, &[], &[], false, false, &["bash".into()])
    }

    fn has_triple(args: &[String], a: &str, b: &str, c: &str) -> bool {
        args.windows(3).any(|w| w[0] == a && w[1] == b && w[2] == c)
    }

    fn has_pair(args: &[String], a: &str, b: &str) -> bool {
        args.windows(2).any(|w| w[0] == a && w[1] == b)
    }

    #[test]
    fn bwrap_args_nix_store_mounts() {
        let ctx = test_ctx();
        let args = default_args(&ctx);
        assert!(has_triple(&args, "--ro-bind", "/nix/store", "/nix/store"));
        assert!(has_triple(
            &args,
            "--ro-bind",
            "/nix/var/nix/db",
            "/nix/var/nix/db"
        ));
        assert!(has_triple(
            &args,
            "--bind",
            "/nix/var/nix/daemon-socket",
            "/nix/var/nix/daemon-socket"
        ));
    }

    #[test]
    fn bwrap_args_profile_mount() {
        let ctx = test_ctx();
        let args = default_args(&ctx);
        assert!(has_triple(
            &args,
            "--ro-bind",
            "/nix/store/fake-profile",
            "/run/current-system/sw"
        ));
    }

    #[test]
    fn bwrap_args_entrypoint_uses_context_path() {
        let ctx = test_ctx();
        let args = default_args(&ctx);
        let sep_pos = args.iter().position(|a| a == "--").unwrap();
        assert_eq!(
            args[sep_pos + 1],
            "/nix/store/fake-entrypoint/bin/sandbox-entrypoint"
        );
    }

    #[test]
    fn bwrap_args_etc_and_home() {
        let ctx = test_ctx();
        let args = default_args(&ctx);
        assert!(has_triple(&args, "--bind", "/tmp/sandbox/etc", "/etc"));
        assert!(has_triple(
            &args,
            "--bind",
            "/tmp/sandbox/home",
            "/home/testuser"
        ));
    }

    #[test]
    fn bwrap_args_proc_dev_tmpfs() {
        let ctx = test_ctx();
        let args = default_args(&ctx);
        assert!(has_pair(&args, "--proc", "/proc"));
        assert!(has_pair(&args, "--dev", "/dev"));
        assert!(has_pair(&args, "--tmpfs", "/tmp"));
        assert!(has_pair(&args, "--tmpfs", "/var/tmp"));
    }

    #[test]
    fn bwrap_args_pwd_bind() {
        let ctx = test_ctx();
        let args = default_args(&ctx);
        assert!(has_triple(
            &args,
            "--bind",
            "/home/testuser/project",
            "/home/testuser/project"
        ));
    }

    #[test]
    fn bwrap_args_data_dir_mounts() {
        let ctx = test_ctx();
        let args = default_args(&ctx);
        assert!(has_triple(
            &args,
            "--bind",
            "/tmp/sandbox/data/claude",
            "/home/testuser/.claude"
        ));
        assert!(has_triple(
            &args,
            "--bind",
            "/tmp/sandbox/data/codex",
            "/home/testuser/.codex"
        ));
        assert!(has_triple(
            &args,
            "--bind",
            "/tmp/sandbox/data/pi",
            "/home/testuser/.pi"
        ));
        assert!(has_triple(
            &args,
            "--bind",
            "/tmp/sandbox/data/ralphex",
            "/home/testuser/.config/ralphex"
        ));
        assert!(has_triple(
            &args,
            "--bind",
            "/tmp/sandbox/data/gh",
            "/home/testuser/.config/gh"
        ));
        assert!(has_triple(
            &args,
            "--bind",
            "/tmp/sandbox/data/revdiff",
            "/home/testuser/.config/revdiff"
        ));
        assert!(has_triple(
            &args,
            "--bind",
            "/tmp/sandbox/data/sops-age",
            "/home/testuser/.config/sops/age"
        ));
        assert!(has_triple(
            &args,
            "--bind",
            "/tmp/sandbox/data/containers",
            "/home/testuser/.local/share/containers"
        ));
    }

    #[test]
    fn bwrap_args_readonly_config_mounts() {
        let ctx = test_ctx();
        let args = default_args(&ctx);
        assert!(has_triple(
            &args,
            "--ro-bind",
            "/tmp/sandbox/data/git",
            "/home/testuser/.config/git"
        ));
        assert!(has_triple(
            &args,
            "--ro-bind",
            "/tmp/sandbox/data/ssh",
            "/home/testuser/.ssh"
        ));
    }

    #[test]
    fn bwrap_args_ssh_writable_overlays() {
        let ctx = test_ctx();
        let args = default_args(&ctx);
        assert!(has_triple(
            &args,
            "--bind",
            "/tmp/sandbox/data/ssh/known_hosts",
            "/home/testuser/.ssh/known_hosts"
        ));
        assert!(has_triple(
            &args,
            "--bind",
            "/tmp/sandbox/data/ssh/allowed_signers",
            "/home/testuser/.ssh/allowed_signers"
        ));
    }

    #[test]
    fn bwrap_args_environment() {
        let ctx = test_ctx();
        let term_vars = vec![
            ("TERM".into(), "xterm-256color".into()),
            (
                "YOLO_HOST_TERMINFO_DIRS".into(),
                "/nix/store/aaa-share-terminfo:/nix/store/bbb-share-terminfo".into(),
            ),
        ];
        let args = build_bwrap_args(&ctx, &[], &term_vars, false, false, &["bash".into()]);
        assert!(args.contains(&"--clearenv".to_string()));
        assert!(has_triple(&args, "--setenv", "HOME", "/home/testuser"));
        assert!(has_triple(&args, "--setenv", "USER", "testuser"));
        assert!(has_triple(
            &args,
            "--setenv",
            "XDG_RUNTIME_DIR",
            "/run/user/1000"
        ));
        assert!(has_triple(&args, "--setenv", "TERM", "xterm-256color"));
        assert!(has_triple(
            &args,
            "--setenv",
            "YOLO_HOST_TERMINFO_DIRS",
            "/nix/store/aaa-share-terminfo:/nix/store/bbb-share-terminfo"
        ));
    }

    #[test]
    fn bwrap_args_no_terminfo_dirs() {
        let ctx = test_ctx();
        let term_vars = vec![("TERM".into(), "xterm-256color".into())];
        let args = build_bwrap_args(&ctx, &[], &term_vars, false, false, &["bash".into()]);
        assert!(has_triple(&args, "--setenv", "TERM", "xterm-256color"));
        assert!(!args.iter().any(|a| a == "YOLO_HOST_TERMINFO_DIRS"));
    }

    #[test]
    fn bwrap_args_namespace_flags() {
        let ctx = test_ctx();
        let args = default_args(&ctx);
        assert!(args.contains(&"--unshare-ipc".to_string()));
        assert!(args.contains(&"--unshare-pid".to_string()));
        assert!(args.contains(&"--unshare-uts".to_string()));
        assert!(args.contains(&"--die-with-parent".to_string()));
        assert!(has_pair(&args, "--chdir", "/home/testuser/project"));
    }

    #[test]
    fn bwrap_args_wide_uid_flags() {
        let ctx = test_ctx();
        let args = build_bwrap_args(&ctx, &[], &[], true, false, &["bash".into()]);
        assert!(args.contains(&"--unshare-user".to_string()));
        assert!(has_pair(&args, "--cap-add", "CAP_SETUID"));
        assert!(has_pair(&args, "--cap-add", "CAP_SETGID"));
    }

    #[test]
    fn bwrap_args_no_wide_uid_no_unshare_user() {
        let ctx = test_ctx();
        let args = default_args(&ctx);
        assert!(!args.contains(&"--unshare-user".to_string()));
    }

    #[test]
    fn bwrap_args_direnv_flag() {
        let ctx = test_ctx();
        let with = build_bwrap_args(&ctx, &[], &[], false, true, &["bash".into()]);
        let without = default_args(&ctx);
        assert!(with.contains(&"--direnv".to_string()));
        assert!(!without.contains(&"--direnv".to_string()));
    }

    #[test]
    fn bwrap_args_command_at_end() {
        let ctx = test_ctx();
        let args = build_bwrap_args(
            &ctx,
            &[],
            &[],
            false,
            false,
            &["bash".into(), "-c".into(), "echo hi".into()],
        );
        let len = args.len();
        assert_eq!(args[len - 3], "bash");
        assert_eq!(args[len - 2], "-c");
        assert_eq!(args[len - 1], "echo hi");
    }

    #[test]
    fn bwrap_args_optional_mounts() {
        let ctx = test_ctx();
        let mounts = vec![
            (MountType::RoBind, "/sys/fs/cgroup"),
            (MountType::DevBind, "/dev/net/tun"),
        ];
        let args = build_bwrap_args(&ctx, &mounts, &[], false, false, &["bash".into()]);
        assert!(has_triple(
            &args,
            "--ro-bind",
            "/sys/fs/cgroup",
            "/sys/fs/cgroup"
        ));
        assert!(has_triple(
            &args,
            "--dev-bind",
            "/dev/net/tun",
            "/dev/net/tun"
        ));
    }

    #[test]
    fn gen_subid_content_typical() {
        let result = gen_subid_content("alice", 1000, 65536);
        assert_eq!(result, "alice:1:999\nalice:1001:64536\n");
    }

    #[test]
    fn gen_subid_content_minimum_id() {
        let result = gen_subid_content("bob", 2, 65536);
        assert_eq!(result, "bob:1:1\nbob:3:65534\n");
    }

    #[test]
    fn gen_subid_content_ranges_cover_expected() {
        let id = 1000u32;
        let count = 65536u32;
        let result = gen_subid_content("user", id, count);
        let lines: Vec<&str> = result.lines().collect();
        assert_eq!(lines.len(), 2);

        let parts1: Vec<&str> = lines[0].split(':').collect();
        let start1: u32 = parts1[1].parse().unwrap();
        let count1: u32 = parts1[2].parse().unwrap();
        assert_eq!(start1, 1);
        assert_eq!(count1, id - 1);

        let parts2: Vec<&str> = lines[1].split(':').collect();
        let start2: u32 = parts2[1].parse().unwrap();
        let count2: u32 = parts2[2].parse().unwrap();
        assert_eq!(start2, id + 1);
        assert_eq!(count2, count - id);

        // Total mapped IDs (excluding 0 and the real id): count - 1
        assert_eq!(count1 + count2, count - 1);
    }

    #[test]
    fn direnv_not_detected_without_env_var() {
        assert!(!detect_direnv(Path::new("/nonexistent/path")));
    }

    #[test]
    fn tempdir_cleanup_on_drop() {
        let path;
        {
            let tmp = SandboxTempDir::new().unwrap();
            path = tmp.path().to_path_buf();
            assert!(path.exists());
            // Create a restricted subdirectory to test chmod behavior
            let inner = path.join("restricted");
            fs::create_dir(&inner).unwrap();
            fs::set_permissions(&inner, fs::Permissions::from_mode(0o000)).unwrap();
        }
        assert!(!path.exists());
    }

    #[test]
    fn resolve_host_terminfo_dirs_basic() {
        let tmp = tempfile::tempdir().unwrap();
        let target1 = tmp.path().join("target1");
        let target2 = tmp.path().join("target2");
        fs::create_dir(&target1).unwrap();
        fs::create_dir(&target2).unwrap();
        let link1 = tmp.path().join("link1");
        let link2 = tmp.path().join("link2");
        std::os::unix::fs::symlink(&target1, &link1).unwrap();
        std::os::unix::fs::symlink(&target2, &link2).unwrap();

        let raw = format!("{}:{}", link1.display(), link2.display());
        let result = resolve_host_terminfo_dirs(&raw).unwrap();

        let expected = format!(
            "{}:{}",
            fs::canonicalize(&target1).unwrap().display(),
            fs::canonicalize(&target2).unwrap().display()
        );
        assert_eq!(result, expected);
    }

    #[test]
    fn resolve_host_terminfo_dirs_skips_missing() {
        let tmp = tempfile::tempdir().unwrap();
        let valid = tmp.path().join("valid");
        fs::create_dir(&valid).unwrap();
        let bogus = tmp.path().join("does-not-exist");

        let raw = format!("{}:{}", bogus.display(), valid.display());
        let result = resolve_host_terminfo_dirs(&raw).unwrap();

        assert_eq!(
            result,
            fs::canonicalize(&valid).unwrap().display().to_string()
        );
    }

    #[test]
    fn resolve_host_terminfo_dirs_dedup() {
        let tmp = tempfile::tempdir().unwrap();
        let target = tmp.path().join("target");
        fs::create_dir(&target).unwrap();
        let linka = tmp.path().join("linka");
        let linkb = tmp.path().join("linkb");
        std::os::unix::fs::symlink(&target, &linka).unwrap();
        std::os::unix::fs::symlink(&target, &linkb).unwrap();

        let raw = format!("{}:{}", linka.display(), linkb.display());
        let result = resolve_host_terminfo_dirs(&raw).unwrap();

        let canonical = fs::canonicalize(&target).unwrap().display().to_string();
        assert_eq!(result, canonical);
    }

    #[test]
    fn resolve_host_terminfo_dirs_empty() {
        assert!(resolve_host_terminfo_dirs("").is_none());
        assert!(resolve_host_terminfo_dirs(":").is_none());
        assert!(resolve_host_terminfo_dirs("/nonexistent/a:/nonexistent/b").is_none());
    }

    #[test]
    fn bwrap_args_usrbinenv_symlink_when_set() {
        let mut ctx = test_ctx();
        ctx.usrbinenv = Some(PathBuf::from("/nix/store/fake-coreutils/bin/env"));
        let args = default_args(&ctx);
        assert!(has_triple(
            &args,
            "--symlink",
            "/nix/store/fake-coreutils/bin/env",
            "/usr/bin/env"
        ));
        let symlink_pos = args.iter().position(|a| a == "--symlink").unwrap();
        let sep_pos = args.iter().position(|a| a == "--").unwrap();
        assert!(symlink_pos < sep_pos);
    }

    #[test]
    fn bwrap_args_usrbinenv_omitted_when_none() {
        let ctx = test_ctx();
        let args = default_args(&ctx);
        assert!(
            !args
                .windows(3)
                .any(|w| w[0] == "--symlink" && w[2] == "/usr/bin/env")
        );
    }

    #[test]
    fn parse_optional_env_path_treats_none_and_empty_as_absent() {
        assert!(parse_optional_env_path(None).is_none());
        assert!(parse_optional_env_path(Some(String::new())).is_none());
        assert_eq!(
            parse_optional_env_path(Some("/nix/store/x/bin/env".into())),
            Some(PathBuf::from("/nix/store/x/bin/env"))
        );
    }
}
