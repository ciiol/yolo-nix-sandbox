"""Podman and Docker compatibility tests for the yolo sandbox."""

import json


def test_podman_info(yolo, requires_wide_uid):
    """podman info succeeds and reports expected backend configuration."""
    result = yolo("podman", "info", "--format", "json", check=False)
    assert result.returncode == 0, f"podman info failed: {result.stderr}"

    info = json.loads(result.stdout)
    host = info["host"]
    assert host["security"]["rootless"] is True
    assert host["ociRuntime"]["name"] == "crun"

    store = info["store"]
    assert store["graphDriverName"] == "overlay"


def test_podman_build_and_run(yolo_with_state, requires_wide_uid):
    """Build a busybox image offline, run via podman and docker, verify persistence."""
    build_script = (
        "set -e; dir=$(mktemp -d);"
        " cp $(readlink -f $(which busybox)) $dir/busybox;"
        " printf 'FROM scratch\\nCOPY busybox /busybox\\n' > $dir/Dockerfile;"
        " podman build -t busybox-test $dir"
    )
    result = yolo_with_state("bash", "-c", build_script, check=False)
    assert result.returncode == 0, f"podman build failed: {result.stderr}"

    result = yolo_with_state(
        "podman", "run", "--rm", "busybox-test", "/busybox", "echo", "hello", check=False
    )
    assert result.returncode == 0, f"podman run failed: {result.stderr}"
    assert result.stdout.strip() == "hello"

    result = yolo_with_state(
        "docker", "run", "--rm", "busybox-test", "/busybox", "echo", "hello", check=False
    )
    assert result.returncode == 0, f"docker run failed: {result.stderr}"
    assert result.stdout.strip() == "hello"

    result = yolo_with_state("podman", "image", "exists", "busybox-test", check=False)
    assert result.returncode == 0, "busybox-test image did not persist across sandbox runs"


def test_podman_uid_mappings(yolo, requires_wide_uid):
    """Podman reports wide UID/GID mappings matching the sandbox's uid_map."""
    result = yolo("podman", "info", "--format", "json", check=False)
    assert result.returncode == 0, f"podman info failed: {result.stderr}"

    id_mappings = json.loads(result.stdout)["host"]["idMappings"]
    uid_total = sum(m["size"] for m in id_mappings["uidmap"])
    gid_total = sum(m["size"] for m in id_mappings["gidmap"])
    assert uid_total == gid_total, "UID and GID mapping sizes should match"
    assert uid_total > 1, f"expected multi-UID mappings in wide-UID sandbox, got {uid_total}"

    result = yolo("cat", "/proc/self/uid_map", check=False)
    assert result.returncode == 0, f"reading uid_map failed: {result.stderr}"

    sandbox_uid_total = sum(int(line.split()[2]) for line in result.stdout.strip().splitlines())
    assert uid_total + 1 == sandbox_uid_total, (
        f"podman uid_total + 1 ({uid_total}) != sandbox uid_map total ({sandbox_uid_total})"
    )
