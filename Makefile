.DEFAULT_GOAL := help

.PHONY: help setup

help:
	@echo "setup    install pinned host tools into /usr/local/bin"
	@echo "         runs: bash scripts/setup.sh"

setup:
	@echo "+ bash scripts/setup.sh"
	@bash scripts/setup.sh
