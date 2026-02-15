"""Python library availability tests for the yolo sandbox."""

import pytest

PYTHON_LIBRARIES = [
    ("numpy", "numpy"),
    ("pandas", "pandas"),
    ("scipy", "scipy"),
    ("matplotlib", "matplotlib"),
    ("requests", "requests"),
    ("beautifulsoup4", "bs4"),
    ("lxml", "lxml"),
    ("scikit-learn", "sklearn"),
    ("sympy", "sympy"),
    ("pillow", "PIL"),
    ("openpyxl", "openpyxl"),
    ("pyyaml", "yaml"),
    ("httpx", "httpx"),
]


@pytest.mark.parametrize(
    ("package", "module"),
    PYTHON_LIBRARIES,
    ids=[lib[0] for lib in PYTHON_LIBRARIES],
)
def test_python_library_importable(yolo, package, module):
    """Each expected Python library is importable inside the sandbox."""
    result = yolo("python3", "-c", f"import {module}", check=False)
    assert result.returncode == 0, (
        f"Python library '{package}' (import {module}) not importable: {result.stderr}"
    )
