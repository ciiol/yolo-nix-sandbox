use std::fs;
use std::os::unix::fs as unix_fs;
use std::os::unix::fs::PermissionsExt;
use std::path::Path;

use anyhow::{Context, Result};
use nix::unistd::{Group, User, getgid, getuid};

fn format_passwd(user: &str, uid: u32, gid: u32, home: &str) -> String {
    format!(
        "root:x:0:0:root:/root:/bin/bash\n\
         nobody:x:65534:65534:Nobody:/:/nope\n\
         {user}:x:{uid}:{gid}:{user}:{home}:/bin/bash\n"
    )
}

fn format_group(group: &str, gid: u32) -> String {
    format!(
        "root:x:0:\n\
         nobody:x:65534:\n\
         {group}:x:{gid}:\n"
    )
}

pub fn gen_passwd() -> Result<String> {
    let uid = getuid();
    let gid = getgid();
    let user = User::from_uid(uid)
        .context("failed to look up current user")?
        .context("current user not found")?;
    let home = std::env::var("HOME").context("HOME not set")?;
    Ok(format_passwd(&user.name, uid.as_raw(), gid.as_raw(), &home))
}

pub fn gen_group() -> Result<String> {
    let gid = getgid();
    let group = Group::from_gid(gid)
        .context("failed to look up current group")?
        .context("current group not found")?;
    Ok(format_group(&group.name, gid.as_raw()))
}

pub fn gen_hosts() -> String {
    "127.0.0.1 localhost\n::1 localhost\n".to_string()
}

/// Best-effort recursive copy: continues past individual file errors
/// to match `cp -a ... 2>/dev/null || true` behavior from the bash version.
fn copy_dir_contents(src: &Path, dst: &Path) {
    let entries = match fs::read_dir(src) {
        Ok(e) => e,
        Err(_) => return,
    };

    for entry in entries.flatten() {
        let src_path = entry.path();
        let dst_path = dst.join(entry.file_name());
        let metadata = match fs::symlink_metadata(&src_path) {
            Ok(m) => m,
            Err(_) => continue,
        };

        if metadata.is_symlink() {
            let Ok(target) = fs::read_link(&src_path) else {
                continue;
            };
            let _ = fs::remove_file(&dst_path);
            let _ = unix_fs::symlink(&target, &dst_path);
        } else if metadata.is_dir() {
            let _ = fs::create_dir_all(&dst_path);
            copy_dir_contents(&src_path, &dst_path);
        } else {
            let _ = fs::copy(&src_path, &dst_path);
        }
    }
}

fn set_writable_recursive(path: &Path) -> Result<()> {
    let metadata = fs::symlink_metadata(path)?;
    if metadata.is_symlink() {
        return Ok(());
    }
    let mode = metadata.permissions().mode();
    fs::set_permissions(path, fs::Permissions::from_mode(mode | 0o200))?;
    if metadata.is_dir() {
        for entry in fs::read_dir(path)? {
            set_writable_recursive(&entry?.path())?;
        }
    }
    Ok(())
}

pub fn build_etc(etc_dir: &Path, sandbox_etc: &Path) -> Result<()> {
    let src = sandbox_etc.join("etc");
    if src.is_dir() {
        copy_dir_contents(&src, etc_dir);
    }
    let _ = set_writable_recursive(etc_dir);

    for name in &["passwd", "group", "hosts", "resolv.conf"] {
        let _ = fs::remove_file(etc_dir.join(name));
    }

    fs::write(etc_dir.join("passwd"), gen_passwd()?)?;
    fs::write(etc_dir.join("group"), gen_group()?)?;
    fs::write(etc_dir.join("hosts"), gen_hosts())?;
    // Best-effort: host may not have resolv.conf (e.g. in nix build sandbox)
    let _ = fs::copy("/etc/resolv.conf", etc_dir.join("resolv.conf"));

    let _ = fs::remove_file(etc_dir.join("subuid"));
    let _ = fs::remove_file(etc_dir.join("subgid"));

    Ok(())
}

#[cfg(test)]
mod tests {
    use super::*;
    use tempfile::TempDir;

    #[test]
    fn format_passwd_output() {
        let result = format_passwd("testuser", 1000, 1000, "/home/testuser");
        let lines: Vec<&str> = result.lines().collect();
        assert_eq!(lines.len(), 3);
        assert_eq!(lines[0], "root:x:0:0:root:/root:/bin/bash");
        assert_eq!(lines[1], "nobody:x:65534:65534:Nobody:/:/nope");
        assert_eq!(
            lines[2],
            "testuser:x:1000:1000:testuser:/home/testuser:/bin/bash"
        );
    }

    #[test]
    fn format_passwd_different_uid_gid() {
        let result = format_passwd("alice", 501, 20, "/Users/alice");
        assert!(result.contains("alice:x:501:20:alice:/Users/alice:/bin/bash"));
    }

    #[test]
    fn format_group_output() {
        let result = format_group("testgroup", 1000);
        let lines: Vec<&str> = result.lines().collect();
        assert_eq!(lines.len(), 3);
        assert_eq!(lines[0], "root:x:0:");
        assert_eq!(lines[1], "nobody:x:65534:");
        assert_eq!(lines[2], "testgroup:x:1000:");
    }

    #[test]
    fn hosts_output() {
        let result = gen_hosts();
        assert_eq!(result, "127.0.0.1 localhost\n::1 localhost\n");
    }

    #[test]
    fn gen_passwd_succeeds() {
        let result = gen_passwd().unwrap();
        assert!(result.starts_with("root:x:0:0:root:/root:/bin/bash\n"));
        assert!(result.contains("nobody:x:65534:65534:Nobody:/:/nope\n"));
        assert_eq!(result.lines().count(), 3);
        let last_line = result.lines().last().unwrap();
        assert!(last_line.ends_with(":/bin/bash"));
    }

    #[test]
    fn gen_group_succeeds() {
        let result = gen_group().unwrap();
        assert!(result.starts_with("root:x:0:\n"));
        assert!(result.contains("nobody:x:65534:\n"));
        assert_eq!(result.lines().count(), 3);
    }

    #[test]
    fn build_etc_with_mock_sandbox() {
        let tmp = TempDir::new().unwrap();
        let sandbox_etc = tmp.path().join("sandbox");
        let sandbox_etc_inner = sandbox_etc.join("etc");
        fs::create_dir_all(&sandbox_etc_inner).unwrap();

        fs::write(sandbox_etc_inner.join("some_config"), "config_data").unwrap();
        fs::write(sandbox_etc_inner.join("subuid"), "user:100000:65536").unwrap();
        fs::write(sandbox_etc_inner.join("subgid"), "user:100000:65536").unwrap();
        unix_fs::symlink("/nix/store/fake-path", sandbox_etc_inner.join("linked")).unwrap();

        let etc_dir = tmp.path().join("etc");
        fs::create_dir(&etc_dir).unwrap();

        build_etc(&etc_dir, &sandbox_etc).unwrap();

        let passwd = fs::read_to_string(etc_dir.join("passwd")).unwrap();
        assert!(passwd.starts_with("root:x:0:0:"));
        assert!(passwd.contains("nobody:x:65534:"));

        let group = fs::read_to_string(etc_dir.join("group")).unwrap();
        assert!(group.starts_with("root:x:0:"));
        assert!(group.contains("nobody:x:65534:"));

        let hosts = fs::read_to_string(etc_dir.join("hosts")).unwrap();
        assert_eq!(hosts, "127.0.0.1 localhost\n::1 localhost\n");

        // resolv.conf only present if host has /etc/resolv.conf

        assert!(!etc_dir.join("subuid").exists());
        assert!(!etc_dir.join("subgid").exists());

        assert_eq!(
            fs::read_to_string(etc_dir.join("some_config")).unwrap(),
            "config_data"
        );

        let link_target = fs::read_link(etc_dir.join("linked")).unwrap();
        assert_eq!(link_target.to_str().unwrap(), "/nix/store/fake-path");
    }

    #[test]
    fn build_etc_without_sandbox_dir() {
        let tmp = TempDir::new().unwrap();
        let sandbox_etc = tmp.path().join("nonexistent");
        let etc_dir = tmp.path().join("etc");
        fs::create_dir(&etc_dir).unwrap();

        build_etc(&etc_dir, &sandbox_etc).unwrap();

        assert!(etc_dir.join("passwd").exists());
        assert!(etc_dir.join("group").exists());
        assert!(etc_dir.join("hosts").exists());
    }

    #[test]
    fn build_etc_overrides_existing_files() {
        let tmp = TempDir::new().unwrap();
        let sandbox_etc = tmp.path().join("sandbox");
        let sandbox_etc_inner = sandbox_etc.join("etc");
        fs::create_dir_all(&sandbox_etc_inner).unwrap();

        fs::write(sandbox_etc_inner.join("passwd"), "stale").unwrap();
        fs::write(sandbox_etc_inner.join("hosts"), "stale").unwrap();

        let etc_dir = tmp.path().join("etc");
        fs::create_dir(&etc_dir).unwrap();

        build_etc(&etc_dir, &sandbox_etc).unwrap();

        let passwd = fs::read_to_string(etc_dir.join("passwd")).unwrap();
        assert!(passwd.starts_with("root:x:0:0:"));
        assert!(!passwd.contains("stale"));

        let hosts = fs::read_to_string(etc_dir.join("hosts")).unwrap();
        assert_eq!(hosts, "127.0.0.1 localhost\n::1 localhost\n");
    }
}
