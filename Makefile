.PHONY: setup app install uninstall check

setup:
	uv sync

app:
	scripts/build_app.sh

install: setup app
	scripts/install.sh

uninstall:
	scripts/uninstall.sh

check:
	uv run pytest
	cd app && swift run selftest
