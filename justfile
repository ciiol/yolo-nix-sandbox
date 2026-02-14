default: check

check: lint test

lint:
    nix flake check

fmt:
    nix fmt

test:
    pytest tests/ -v
