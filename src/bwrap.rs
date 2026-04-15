use std::fs::{self, File, OpenOptions};
use std::io::{Read as _, Write};
use std::os::unix::io::OwnedFd;
use std::path::Path;
use std::process::{Child, Command, ExitStatus};

use anyhow::{Context, Result, bail};
use command_fds::{CommandFdExt, FdMapping};
use nix::sys::stat::Mode;
use nix::unistd::{getgid, getuid, mkfifo};

use crate::uid::{SubIdRange, WideUidConfig};

/// Build the argument vector for newuidmap/newgidmap.
/// Maps three ranges to create a full user namespace mapping:
/// 1. [0, id) -> [range.start, range.start + id) — subordinate IDs before real ID
/// 2. id -> id — identity map for the real user
/// 3. [id+1, ...) -> [range.start + id, ...) — subordinate IDs after real ID
/// Requires id >= 2 and range.count > id (enforced by is_valid_wide_uid).
fn id_map_args(child_pid: u32, id: u32, range: &SubIdRange) -> Vec<String> {
    debug_assert!(id >= 2, "id_map_args requires id >= 2, got {id}");
    debug_assert!(
        range.count > id,
        "id_map_args requires range.count > id, got count={}, id={id}",
        range.count
    );
    vec![
        child_pid.to_string(),
        "0".to_string(),
        range.start.to_string(),
        id.to_string(),
        id.to_string(),
        id.to_string(),
        "1".to_string(),
        (id + 1).to_string(),
        (range.start + id).to_string(),
        (range.count - id).to_string(),
    ]
}

fn build_simple_command(bwrap_args: &[String]) -> Command {
    let mut cmd = Command::new("setpriv");
    cmd.args(["--ambient-caps", "-all", "--"]);
    cmd.arg("bwrap");
    cmd.args(bwrap_args);
    cmd
}

fn build_wide_uid_command(bwrap_args: &[String]) -> Command {
    let mut cmd = Command::new("setpriv");
    cmd.args(["--ambient-caps", "-all", "--"]);
    cmd.arg("bwrap");
    cmd.args(["--info-fd", "3", "--userns-block-fd", "4"]);
    cmd.args(bwrap_args);
    cmd
}

/// Run bwrap in simple mode (no user namespace UID mapping).
pub fn run_simple(bwrap_args: &[String]) -> Result<ExitStatus> {
    build_simple_command(bwrap_args)
        .status()
        .context("failed to execute bwrap")
}

/// RAII guard for wide-UID bwrap cleanup.
/// On drop: closes block fd, kills bwrap, waits for exit.
struct BwrapGuard {
    child: Option<Child>,
    block_fd: Option<File>,
}

impl BwrapGuard {
    fn new(child: Child, block_fd: File) -> Self {
        Self {
            child: Some(child),
            block_fd: Some(block_fd),
        }
    }

    /// Unblock bwrap by writing to the block fd, then wait for exit.
    fn unblock_and_wait(&mut self) -> Result<ExitStatus> {
        if let Some(mut fd) = self.block_fd.take() {
            writeln!(fd).context("failed to unblock bwrap")?;
        }
        let status = self
            .child
            .as_mut()
            .context("bwrap process already consumed")?
            .wait()
            .context("failed to wait for bwrap")?;
        self.child.take();
        Ok(status)
    }
}

impl Drop for BwrapGuard {
    fn drop(&mut self) {
        drop(self.block_fd.take());
        if let Some(mut child) = self.child.take() {
            let _ = child.kill();
            let _ = child.wait();
        }
    }
}

/// Run bwrap with wide-UID user namespace mapping.
pub fn run_wide_uid(
    bwrap_args: &[String],
    config: &WideUidConfig,
    tmpdir: &Path,
) -> Result<ExitStatus> {
    let uid = getuid().as_raw();
    let gid = getgid().as_raw();

    let fifo_dir = tmpdir.join("bwrap-fifos");
    fs::create_dir(&fifo_dir).context("failed to create FIFO directory")?;

    let info_fifo = fifo_dir.join("info");
    let block_fifo = fifo_dir.join("block");
    let fifo_mode = Mode::S_IRUSR | Mode::S_IWUSR;
    mkfifo(&info_fifo, fifo_mode).context("failed to create info FIFO")?;
    mkfifo(&block_fifo, fifo_mode).context("failed to create block FIFO")?;

    // Open block FIFO read-write so the child's read-open doesn't block
    let block_fd = OpenOptions::new()
        .read(true)
        .write(true)
        .open(&block_fifo)
        .context("failed to open block FIFO")?;

    // Open info FIFO read-write for non-blocking open, used as write end for child
    let info_rw = OpenOptions::new()
        .read(true)
        .write(true)
        .open(&info_fifo)
        .context("failed to open info FIFO")?;

    // Separate read-only fd for parent to read child PID
    let mut info_read = OpenOptions::new()
        .read(true)
        .open(&info_fifo)
        .context("failed to open info FIFO for reading")?;

    // Read-only fd for child's userns-block-fd
    let block_read = OpenOptions::new()
        .read(true)
        .open(&block_fifo)
        .context("failed to open block FIFO for reading")?;

    let info_write_fd: OwnedFd = info_rw.into();
    let block_read_fd: OwnedFd = block_read.into();

    let mut cmd = build_wide_uid_command(bwrap_args);
    cmd.fd_mappings(vec![
        FdMapping {
            parent_fd: info_write_fd,
            child_fd: 3,
        },
        FdMapping {
            parent_fd: block_read_fd,
            child_fd: 4,
        },
    ])
    .context("failed to set up fd mappings")?;

    let child = cmd.spawn().context("failed to spawn bwrap")?;

    // Drop command to close parent copies of mapped fds so EOF propagates
    drop(cmd);

    let mut guard = BwrapGuard::new(child, block_fd);

    // bwrap writes multi-line JSON to info-fd, so read until EOF
    let mut info_json = String::new();
    info_read
        .read_to_string(&mut info_json)
        .context("failed to read bwrap info")?;

    if info_json.is_empty() {
        bail!("bwrap exited before writing info");
    }

    let info: serde_json::Value =
        serde_json::from_str(&info_json).context("failed to parse bwrap info JSON")?;
    let child_pid: u32 = info
        .get("child-pid")
        .and_then(|v| v.as_u64())
        .context("missing child-pid in bwrap info")?
        .try_into()
        .context("child-pid out of u32 range")?;

    let uid_args = id_map_args(child_pid, uid, &config.uid_range);
    let uid_status = Command::new("newuidmap")
        .args(&uid_args)
        .status()
        .context("failed to execute newuidmap")?;
    if !uid_status.success() {
        bail!("newuidmap failed");
    }

    let gid_args = id_map_args(child_pid, gid, &config.gid_range);
    let gid_status = Command::new("newgidmap")
        .args(&gid_args)
        .status()
        .context("failed to execute newgidmap")?;
    if !gid_status.success() {
        bail!("newgidmap failed");
    }

    guard.unblock_and_wait()
}

#[cfg(test)]
mod tests {
    use super::*;
    use std::ffi::OsStr;

    #[test]
    fn id_map_args_typical() {
        let range = SubIdRange {
            start: 100000,
            count: 65536,
        };
        let args = id_map_args(42, 1000, &range);
        assert_eq!(
            args,
            vec![
                "42", "0", "100000", "1000", "1000", "1000", "1", "1001", "101000", "64536"
            ]
        );
    }

    #[test]
    fn id_map_args_minimum_uid() {
        let range = SubIdRange {
            start: 100000,
            count: 65536,
        };
        let args = id_map_args(99, 2, &range);
        assert_eq!(
            args,
            vec![
                "99", "0", "100000", "2", "2", "2", "1", "3", "100002", "65534"
            ]
        );
    }

    #[test]
    fn id_map_args_total_mapped_count() {
        let range = SubIdRange {
            start: 200000,
            count: 10000,
        };
        let uid = 500u32;
        let args = id_map_args(1, uid, &range);
        let range1_count: u32 = args[3].parse().unwrap();
        let range2_count: u32 = args[6].parse().unwrap();
        let range3_count: u32 = args[9].parse().unwrap();
        // Total = uid + 1 + (count - uid) = count + 1
        assert_eq!(range1_count + range2_count + range3_count, 10001);
    }

    #[test]
    fn id_map_args_identity_range() {
        let range = SubIdRange {
            start: 100000,
            count: 65536,
        };
        let uid = 1000u32;
        let args = id_map_args(5, uid, &range);
        // Range 2 (identity): inside == outside == uid, count == 1
        assert_eq!(args[4], uid.to_string());
        assert_eq!(args[5], uid.to_string());
        assert_eq!(args[6], "1");
    }

    #[test]
    fn simple_command_has_correct_args() {
        let bwrap_args: Vec<String> = vec![
            "--bind".into(),
            "/foo".into(),
            "/bar".into(),
            "--".into(),
            "/bin/sh".into(),
        ];
        let cmd = build_simple_command(&bwrap_args);
        assert_eq!(cmd.get_program(), "setpriv");
        let args: Vec<&OsStr> = cmd.get_args().collect();
        assert_eq!(
            args,
            vec![
                "--ambient-caps",
                "-all",
                "--",
                "bwrap",
                "--bind",
                "/foo",
                "/bar",
                "--",
                "/bin/sh"
            ]
        );
    }

    #[test]
    fn simple_command_empty_args() {
        let cmd = build_simple_command(&[]);
        let args: Vec<&OsStr> = cmd.get_args().collect();
        assert_eq!(args, vec!["--ambient-caps", "-all", "--", "bwrap"]);
    }

    #[test]
    fn wide_uid_command_includes_fd_args() {
        let bwrap_args: Vec<String> = vec!["--bind".into(), "/a".into(), "/b".into()];
        let cmd = build_wide_uid_command(&bwrap_args);
        assert_eq!(cmd.get_program(), "setpriv");
        let args: Vec<&OsStr> = cmd.get_args().collect();
        assert_eq!(
            args,
            vec![
                "--ambient-caps",
                "-all",
                "--",
                "bwrap",
                "--info-fd",
                "3",
                "--userns-block-fd",
                "4",
                "--bind",
                "/a",
                "/b"
            ]
        );
    }
}
