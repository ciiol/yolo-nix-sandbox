use std::fs;
use std::os::unix::fs::PermissionsExt;
use std::path::Path;

use nix::unistd::{User, getgid, getuid};

#[derive(Debug, Clone)]
pub struct SubIdRange {
    pub start: u32,
    pub count: u32,
}

#[derive(Debug, Clone)]
pub struct WideUidConfig {
    pub uid_range: SubIdRange,
    pub gid_range: SubIdRange,
}

/// Parse a subuid/subgid file and return the range for the given user.
/// Last matching entry wins (matches bash behavior).
pub fn get_subid_range(path: &Path, user: &str) -> Option<SubIdRange> {
    let contents = fs::read_to_string(path).ok()?;
    let mut result = None;
    for line in contents.lines() {
        let parts: Vec<&str> = line.split(':').collect();
        if parts.len() == 3 && parts[0] == user {
            if let (Ok(start), Ok(count)) = (parts[1].parse::<u32>(), parts[2].parse::<u32>()) {
                result = Some(SubIdRange { start, count });
            }
        }
    }
    result
}

fn command_exists(name: &str) -> bool {
    std::env::var_os("PATH")
        .map(|path| {
            std::env::split_paths(&path).any(|dir| {
                let candidate = dir.join(name);
                candidate.is_file()
                    && candidate
                        .metadata()
                        .map(|m| m.permissions().mode() & 0o111 != 0)
                        .unwrap_or(false)
            })
        })
        .unwrap_or(false)
}

fn is_valid_wide_uid(uid: u32, gid: u32, uid_range: &SubIdRange, gid_range: &SubIdRange) -> bool {
    uid >= 2 && gid >= 2 && uid < uid_range.count && gid < gid_range.count
}

/// Check if the host supports wide UID mapping for user namespaces.
pub fn detect_wide_uid_support() -> Option<WideUidConfig> {
    let uid = getuid().as_raw();
    let gid = getgid().as_raw();
    let user = User::from_uid(nix::unistd::Uid::from_raw(uid)).ok()??;

    let subuid_path = Path::new("/etc/subuid");
    let subgid_path = Path::new("/etc/subgid");

    if !subuid_path.is_file() || !subgid_path.is_file() {
        return None;
    }

    if !command_exists("newuidmap") || !command_exists("newgidmap") {
        return None;
    }

    let uid_range = get_subid_range(subuid_path, &user.name)?;
    let gid_range = get_subid_range(subgid_path, &user.name)?;

    if !is_valid_wide_uid(uid, gid, &uid_range, &gid_range) {
        return None;
    }

    Some(WideUidConfig {
        uid_range,
        gid_range,
    })
}

#[cfg(test)]
mod tests {
    use super::*;
    use tempfile::TempDir;

    fn write_subid_file(dir: &Path, name: &str, contents: &str) -> std::path::PathBuf {
        let path = dir.join(name);
        fs::write(&path, contents).unwrap();
        path
    }

    #[test]
    fn get_subid_range_valid() {
        let tmp = TempDir::new().unwrap();
        let path = write_subid_file(tmp.path(), "subuid", "alice:100000:65536\n");
        let range = get_subid_range(&path, "alice").unwrap();
        assert_eq!(range.start, 100000);
        assert_eq!(range.count, 65536);
    }

    #[test]
    fn get_subid_range_missing_user() {
        let tmp = TempDir::new().unwrap();
        let path = write_subid_file(tmp.path(), "subuid", "alice:100000:65536\n");
        assert!(get_subid_range(&path, "bob").is_none());
    }

    #[test]
    fn get_subid_range_malformed_lines() {
        let tmp = TempDir::new().unwrap();
        let contents = "badline\n\
                        alice:notanumber:65536\n\
                        bob:100000:notanumber\n\
                        carol:200000:65536\n";
        let path = write_subid_file(tmp.path(), "subuid", contents);

        assert!(get_subid_range(&path, "alice").is_none());
        assert!(get_subid_range(&path, "bob").is_none());
        let range = get_subid_range(&path, "carol").unwrap();
        assert_eq!(range.start, 200000);
        assert_eq!(range.count, 65536);
    }

    #[test]
    fn get_subid_range_last_match_wins() {
        let tmp = TempDir::new().unwrap();
        let contents = "alice:100000:65536\n\
                        alice:200000:32768\n";
        let path = write_subid_file(tmp.path(), "subuid", contents);
        let range = get_subid_range(&path, "alice").unwrap();
        assert_eq!(range.start, 200000);
        assert_eq!(range.count, 32768);
    }

    #[test]
    fn get_subid_range_empty_file() {
        let tmp = TempDir::new().unwrap();
        let path = write_subid_file(tmp.path(), "subuid", "");
        assert!(get_subid_range(&path, "alice").is_none());
    }

    #[test]
    fn get_subid_range_missing_file() {
        let path = Path::new("/tmp/nonexistent-subuid-test-file");
        assert!(get_subid_range(path, "alice").is_none());
    }

    #[test]
    fn valid_wide_uid_typical() {
        let uid_range = SubIdRange {
            start: 100000,
            count: 65536,
        };
        let gid_range = SubIdRange {
            start: 100000,
            count: 65536,
        };
        assert!(is_valid_wide_uid(1000, 1000, &uid_range, &gid_range));
    }

    #[test]
    fn valid_wide_uid_boundary_uid_2() {
        let uid_range = SubIdRange {
            start: 100000,
            count: 65536,
        };
        let gid_range = SubIdRange {
            start: 100000,
            count: 65536,
        };
        assert!(is_valid_wide_uid(2, 2, &uid_range, &gid_range));
    }

    #[test]
    fn invalid_wide_uid_uid_below_2() {
        let uid_range = SubIdRange {
            start: 100000,
            count: 65536,
        };
        let gid_range = SubIdRange {
            start: 100000,
            count: 65536,
        };
        assert!(!is_valid_wide_uid(1, 1000, &uid_range, &gid_range));
        assert!(!is_valid_wide_uid(0, 1000, &uid_range, &gid_range));
    }

    #[test]
    fn invalid_wide_uid_gid_below_2() {
        let uid_range = SubIdRange {
            start: 100000,
            count: 65536,
        };
        let gid_range = SubIdRange {
            start: 100000,
            count: 65536,
        };
        assert!(!is_valid_wide_uid(1000, 1, &uid_range, &gid_range));
        assert!(!is_valid_wide_uid(1000, 0, &uid_range, &gid_range));
    }

    #[test]
    fn invalid_wide_uid_uid_ge_count() {
        let uid_range = SubIdRange {
            start: 100000,
            count: 1000,
        };
        let gid_range = SubIdRange {
            start: 100000,
            count: 65536,
        };
        // uid == count
        assert!(!is_valid_wide_uid(1000, 500, &uid_range, &gid_range));
        // uid > count
        assert!(!is_valid_wide_uid(1001, 500, &uid_range, &gid_range));
    }

    #[test]
    fn invalid_wide_uid_gid_ge_count() {
        let uid_range = SubIdRange {
            start: 100000,
            count: 65536,
        };
        let gid_range = SubIdRange {
            start: 100000,
            count: 500,
        };
        // gid == count
        assert!(!is_valid_wide_uid(1000, 500, &uid_range, &gid_range));
        // gid > count
        assert!(!is_valid_wide_uid(1000, 501, &uid_range, &gid_range));
    }
}
