default: check

check:
    nix flake check
    pytest tests/

fmt:
    nix fmt
