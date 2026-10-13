# AGENTS.md

Instructions for AI coding agents (Claude Code, Codex, Cursor, etc.) working in this repository. Humans: read [`README.md`](README.md) and [`_docs/00--project-brief.md`](_docs/00--project-brief.md) first; this file only adds agent-specific rules.

## What this project is

Tooling to create **disposable single-VM demo environments** on AWS and GCP with Terraform, connect via VS Code Remote-SSH, auto-expire them, and estimate costs from provider price APIs. Status: **design phase**. It is also a **Terraform learning project** for its owner, and **Terraform state is stored locally on purpose**. If a file, command or module mentioned in the docs doesn't exist, it hasn't been built — say so; don't invent it.

## Hard rules (cost and security)

1. **Never run `terraform apply`, `terraform destroy`, or any command that creates, modifies or deletes cloud resources.** You may run `init -backend=false`, `validate`, `fmt` and `plan` only when the human has set up credentials and explicitly asked. Creating resources costs real money.
2. **Never read, print, log, commit or ask for secrets** (cloud credentials, API tokens, PATs, private keys, `*.tfvars` with real values, `.env`). If you need a value, use a placeholder and tell the human what to set.
3. **Never put secrets in `user_data`, cloud-init templates, Terraform variable defaults, test fixtures or docs.** Secrets are pushed over SSH at runtime or fetched by instance identity (AWS/GCP).
4. **Never open inbound ports to `0.0.0.0/0`.** SSH ingress comes from `allowed_cidrs` (required; tooling may fill it with the caller's detected public IP as /32, never a wide range). App ports are reached through SSH forwarding or a private network.
5. **Every cloud resource you define must carry the standard tags/labels:** `managed-by=demo-machines`, `owner`, `expires_at`. A resource without them is a bug — the reaper can't see it.
6. **Do not add Kubernetes, Ansible, a web UI, a third provider or multi-user features.** They're explicit non-goals (brief §3). Providers are AWS and GCP. If you think another is needed, stop and ask with a concrete pain that justifies it.
7. **Do not hardcode prices** anywhere except `pricing/overrides.yaml` (value + date + source URL) and test fixtures.
8. **Don't scrape third-party price sites or marketing pages.** Use provider APIs. Aggregators were found to be stale and inconsistent.
9. **Never read, print, diff, paste or commit Terraform state** (`state/`, `*.tfstate`, `*.tfstate.backup`). It contains secrets. Don't add a remote backend — local state is a deliberate decision.
10. **Tailscale and public tunnels (e.g. Cloudflare Tunnel) are opt-in fallbacks**, never part of the default flow. Don't wire them into a default path.
11. **No GPU profiles or GPU resources before the reaper exists** (brief §10, Phase 2).

## Commands

> If a command below fails because it doesn't exist yet, report that rather than creating a workaround.

```bash
make setup                           # bash scripts/setup.sh — installs pinned tools into /usr/local/bin

# Terraform (per provider root: terraform/{aws,gcp})
terraform fmt -check -recursive
terraform -chdir=terraform/<provider> init -backend=false
terraform -chdir=terraform/<provider> validate
tflint --recursive
trivy config .                       # the chosen scanner; do not also add checkov

# TypeScript (pricing, reaper, ssh-config)
npm ci
npm run typecheck
npm run lint
npm test                             # unit tests use recorded fixtures — never live APIs
npm run build

# Secrets
gitleaks detect --no-banner
```

All of the above must pass before you call work done.

## Repository layout

```
terraform/<provider>/     one root per provider; identical variable names across providers
terraform/modules/        only genuinely shared code (e.g. cloud-init rendering)
bootstrap/                cloud-init template + idempotent bootstrap.sh
src/pricing/              provider fetchers → normalised price model → report
src/reaper/               list/delete expired tagged resources across providers
src/ssh-config/           writes ~/.ssh/config.d/demo-machines
profiles/                 *.example.tfvars committed; real *.tfvars gitignored
state/                    local Terraform state, one file per provider+profile; gitignored; SECRET
pricing/usage-plans/      YAML usage plans
pricing/overrides.yaml    manual price overrides (dated, sourced)
reports/                  generated output, gitignored
```

## Conventions

### Terraform
- Pin Terraform and provider versions. Don't use `latest` or unbounded ranges.
- **Same variable names and meanings in every provider root** (see README → Configuration). Adding a variable to one root means adding it to all, or documenting why not.
- Sizes are a **hand-curated map** per provider (`small`, `medium`, `large`, `gpu-24`, `gpu-48`). Don't build an automatic spec→instance matcher.
- Variables holding secrets use `sensitive = true`, **but remember state still stores them** — prefer not to pass secrets through Terraform at all.
- Outputs needed by tooling: public IP, SSH user, instance id, `expires_at`.
- Keep provider-specific logic inside that provider's root. Don't write "universal" modules that need `count`/`for_each` gymnastics to cover both providers.
- **This is a learning project.** Prefer simple, explicit, readable HCL over clever abstractions. Don't extract a module until the duplication is real. When you introduce a Terraform construct that's new to the codebase (data source, `templatefile`, `lifecycle`, `moved`, `import`, …), explain in the commit/PR message what it does and why — briefly.
- **No provisioners** (`remote-exec`/`local-exec`) unless there's no alternative; if you use one, explain why.
- The Makefile **prints the underlying `terraform` command** it runs. Don't hide Terraform behind opaque wrappers.
- State is local, one file per provider+profile, selected through backend config (e.g. `terraform init -backend-config="path=../../state/<provider>-<profile>.tfstate"` — confirm exact flags against current docs).

### Bootstrap
- `bootstrap/bootstrap.sh` is **idempotent** and runnable standalone over SSH. Running it twice must not break anything.
- Prefer cloud-init where the provider supports it; fall back to running the same script over SSH. Don't maintain two divergent bootstraps.

### TypeScript
- Strict mode. No `any` without a comment explaining why.
- One language for tooling (TypeScript). Don't add Python scripts.
- Provider API clients are thin; response parsing is validated (e.g. with a schema) because provider payloads change.
- Money is stored as integer minor units or a decimal library — never floats — with an explicit **currency** and **tax-inclusive/exclusive** flag.

## Pricing model rules (easy to get wrong)

- **GCP** prices compute as per-vCPU-hour + per-GB-RAM-hour by family, with separate SKUs for disks, GPUs and IPs. Instance price is *composed*; don't expect a per-instance SKU.
- **AWS** Price List API is served from only a few regions regardless of the region priced. Never download bulk offer files.
- Model billing granularity per provider, with a test. Confirm AWS's per-second minimum and GCP's granularity from current docs. Don't copy one provider's rule onto the other.
- Always include disk, public IP and snapshots when the lifecycle implies them, and exclude VAT unless the plan says otherwise.
- Every report prints **data age** and flags **overridden** prices.

## Known traps

- **Stopped ≠ free.** On AWS and GCP, stopping an instance stops compute billing. The root disk and the public IP keep billing. Never describe a stop as "no cost".
- **AWS GPU quota** is zero on new accounts. Surface the quota error clearly; don't retry in a loop. GCP GPU availability varies by region.
- **A VM shutting itself down is not a reaper.** Compute billing can stop, but the instance, disk and IP remain until deleted.
- **Public IPv4 is billed** on AWS (and external IPs on GCP — verify); IPs change on restart unless reserved.
- **Instance-store NVMe is wiped on stop** (AWS GPU families). Docker data and model weights go on the EBS/persistent root volume.
- **Terraform state contains secrets.** Never commit it, never paste it into an issue.
- **Ubuntu cloud-init is the default path on both providers.** Test it on each image. If it fails, run the same `bootstrap.sh` over SSH. Don't maintain a second bootstrap.
- **Local state is a single point of failure.** Losing it orphans billing machines; the tag-based reaper (works without state) is the backstop. Don't treat state as backed up.

## Testing expectations

- Unit tests for: price normalisation, billing-granularity logic, usage-plan parsing, report generation, reaper expiry logic (with fake clocks), SSH-config rendering.
- **Fixtures** for provider API responses, recorded once and checked in with the date they were recorded. Tests never call live APIs.
- Reaper: **dry-run is the default**; deleting requires an explicit flag. Tests must prove that untagged or non-expired resources are never selected.
- Terraform: `validate` + `tflint` + a security scan in CI. A real `plan` runs only locally by a human with credentials.

## Definition of done

- Typecheck, lint, tests, `terraform fmt/validate`, tflint, security scan and gitleaks all pass.
- No new secret-handling path without a note in the PR explaining where the secret lives and for how long.
- Docs updated: README (if the interface changed), brief (if a decision changed), this file (if a rule changed).
- Anything you could not verify is listed explicitly in the PR description.

## Honesty rules for agents

- **Do not guess provider API fields, instance type names, or prices.** Verify against current provider documentation or recorded responses. If you can't, say "unverified" and mark it in the code with a `// UNVERIFIED:` comment and in the PR description.
- **Don't claim something works if you haven't run it.** State exactly what you ran and the result. "Should work" is not a result.
- **Estimates are estimates.** Never present a cost number without its date, source and accuracy caveat.
- **Push back on scope.** If a requested change adds a non-goal, makes the tool less safe, or increases complexity without a concrete need, say so and propose the smaller alternative.
- **Stop and ask** when: a change would affect billing, touches credentials, widens network exposure, deletes resources, adds Tailscale/a tunnel to a default path, or the docs contradict each other.