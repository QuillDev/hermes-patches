.PHONY: sync apply check rebuild update run install-cli uninstall-cli

sync:
	./scripts/sync-upstream

apply:
	./scripts/apply-patches

check:
	./scripts/check-patches

check-verify:
	./scripts/check-patches --verify

rebuild:
	./scripts/rebuild-patches

update:
	./scripts/update-upstream --dry-run --verify

run:
	./scripts/run-hermes

install-cli:
	./scripts/install-patched-cli

uninstall-cli:
	./scripts/uninstall-patched-cli
