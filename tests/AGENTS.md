# Tests

## Host Independence

Tests must behave identically regardless of the host environment. Never compare sandbox values against live host state (e.g., `os.environ`), because the result changes depending on who runs the tests and how. Instead, assert against a fixed expected value or check a structural property.

Bad — reads from the host and hopes it matches:

```python
def test_term_passthrough(yolo_bin):
    result = subprocess.run([yolo_bin, "run", "printenv", "TERM"], ...)
    assert result.stdout.strip() == os.environ.get("TERM", "xterm-256color")
```

Good — constructs a controlled environment and asserts the contract against it:

```python
def test_term_passthrough(yolo_bin):
    env = {"TERM": "xterm-kitty", ...}
    result = subprocess.run([yolo_bin, "run", "printenv", "TERM"], env=env, ...)
    assert result.stdout.strip() == "xterm-kitty"
```

When complete isolation is impractical (e.g., the test depends on kernel features or user namespace capabilities), skip conditionally with `pytest.skip` rather than silently passing.

## Use Specific Binaries

Run the exact binary you are testing instead of wrapping it in `bash -c`. This makes the test easier to read and removes a shell interpretation layer that can mask failures.

| Instead of | Use |
| ---------------------------------------- | ------------------------------ |
| `yolo("bash", "-c", "command -v jq")` | `yolo("which", "jq")` |
| `yolo("bash", "-c", 'echo "$TERM"')` | `yolo("printenv", "TERM")` |
| `yolo("bash", "-c", "grep foo /a/file")` | `yolo("grep", "foo", "/a/file")` |

Reserve `bash -c` for cases that genuinely need shell features: pipelines, redirections, compound commands, or glob expansion.
