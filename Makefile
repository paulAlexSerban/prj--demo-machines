.DEFAULT_GOAL := help

PROVIDER ?= aws
PROFILE ?= demo-no-llm
export PROVIDER
export PROFILE

.PHONY: help setup fmt validate plan up down open bootstrap status allow-my-ip reaper generate-ssh-key

help:
	@echo "setup          bash scripts/setup.sh"
	@echo "fmt            terraform fmt -recursive"
	@echo "validate       terraform -chdir=terraform/aws init -backend=false && validate"
	@echo "plan           terraform plan (PROVIDER=$(PROVIDER) PROFILE=$(PROFILE))"
	@echo "up             terraform apply — you run this; it spends money"
	@echo "down           terraform destroy"
	@echo "open           clone/start demo on VM, SSH config, forwards, VS Code"
	@echo "bootstrap      clone repo and run startup_command on the VM over SSH"
	@echo "status         show outputs for the current state"
	@echo "allow-my-ip    set allowed_cidrs to this machine's /32; does not apply"
	@echo "reaper         npm run reaper -- --dry-run (does not delete)"
	@echo "variables: PROVIDER PROFILE (defaults aws / demo-no-llm)"

source_env_file:
	@echo "run manually: 'set -a && source .env && set +a'"
	@echo "NOTICE: this will be per terminal session"

setup:
	@echo "+ bash scripts/setup.sh"
	@bash scripts/setup.sh

fmt:
	@echo "+ terraform fmt -recursive"
	@terraform fmt -recursive

validate:
	@echo "+ terraform -chdir=terraform/aws init -backend=false -input=false"
	@terraform -chdir=terraform/aws init -backend=false -input=false
	@echo "+ terraform -chdir=terraform/aws validate"
	@terraform -chdir=terraform/aws validate

plan:
	@echo "+ bash scripts/tf.sh plan"
	@bash scripts/tf.sh plan

up:
	@echo "+ bash scripts/tf.sh up"
	@bash scripts/tf.sh up

down:
	@echo "+ bash scripts/tf.sh down"
	@bash scripts/tf.sh down

open:
	@echo "+ bash scripts/open.sh"
	@bash scripts/open.sh

bootstrap:
	@echo "+ bash scripts/bootstrap-remote.sh"
	@bash scripts/bootstrap-remote.sh

status:
	@echo "+ bash scripts/status.sh"
	@bash scripts/status.sh

allow-my-ip:
	@echo "+ bash scripts/allow-my-ip.sh"
	@bash scripts/allow-my-ip.sh

reaper:
	@echo "+ npm run reaper -- --dry-run"
	@npm run reaper -- --dry-run

generate-ssh-key:
	@echo "+ bash scripts/generate-ssh-key.sh"
	@bash scripts/generate-ssh-key.sh