# Demo Machines — Gated Implementation Plan

Derived from [`00--project-brief.md`](00--project-brief.md) §10, [`README.md`](../README.md) and [`AGENTS.md`](../AGENTS.md). Nothing is built yet.

## How to read this plan

**Roles (non-negotiable, from AGENTS.md hard rule 1):**

- **Agent** writes code/HCL/docs and runs only *safe* commands: `terraform fmt`, `init -backend=false`, `validate`, `tflint`, trivy/checkov, `npm` typecheck/lint/test/build, gitleaks. Agent runs `terraform plan` only if you have set up credentials and explicitly ask.
- **Human** runs everything that touches a cloud account: `plan` with credentials, `apply`/`up`, `down`, reaper `--delete`, live price fetches, console actions, account/budget setup.
- Agent **never** runs `apply`, `destroy`, or reaper delete, and never reads secrets, `*.tfvars` with real values, or `state/`.

**Every phase has the same shape:**

1. **Agent steps** — small, ordered, each ends in a checkable result.
2. **Gate: DRY** — what you run with no cost/no cloud changes. Must pass to continue.
3. **Gate: LIVE** — what you run that may create or touch billable things (marked 💰). Includes the exact expected outcome and the cleanup/verification step.
4. **Exit criteria** — copied from the brief, checked by you.
5. **Sign-off** — you write "GO" (or list changes) before the agent starts the next phase. Agent stops at the gate and does not start the next phase on its own.

**Standing rules at every gate:** if a step fails, the agent reports the failure and stops rather than adding a workaround. Anything not verified is listed as `UNVERIFIED`. Each phase ends with the full "definition of done" check (typecheck, lint, tests, fmt/validate, tflint, security scan, gitleaks) for whatever exists so far.

---

## Phase −1 — Prerequisites and open decisions (human only, before any code)

Brief §12 lists open decisions that affect billing and security. Resolve them now.

| # | Human action | Output |
|---|---|---|
| −1.1 | **Policy check:** is the demo repo/data/credentials yours, and allowed on a personal account? | Written yes/no in the brief §12 |
| −1.2 | Create **sandbox accounts/projects**: Hetzner project, AWS account (or OU/sub-account) | Accounts exist, nothing running |
| −1.3 | Set **budget alerts** (~$20) on each | Alert visible in console |
| −1.4 | Create **least-privilege API credentials** for Terraform (Hetzner token; AWS IAM user/role scoped to EC2/VPC tags) and store them in your password manager / env, **not** in the repo | Credentials exist; agent never sees them |
| −1.5 | Decide: regions, reaper location (default recommendation: scheduled CI + laptop cron fallback), venue fallback plan | Decisions recorded in brief §12 |
| −1.6 | Install tools: Terraform (pin version), tflint, trivy *or* checkov (pick one), gitleaks, Node 22, make | `terraform version` etc. |
| −1.7 | Request **AWS GPU quota now** (lead time is days). Do not raise beyond need. | Support case opened |

**Gate:** you reply "GO Phase 0". Agent also fixes doc inconsistency: README/AGENTS link to `docs/PROJECT_BRIEF.md`, but the file is `_docs/00--project-brief.md` — ask which name wins, then update links.

---

## Phase 0 — By hand (baseline)

**Goal:** learn what Terraform replaces; produce a measured baseline.

**Agent steps**
- 0.1 Write `_docs/02--phase0-runbook.md`: a fill-in checklist template (create VM in console, install Docker, clone, run, forward ports, open VS Code) with timing columns. No code.
- 0.2 Draft a first version of `bootstrap/bootstrap.sh` *from your notes only after* you finish the run (so it encodes reality, not guesses).

**Gate: DRY** — none (documentation only).

**Gate: LIVE 💰** (Hetzner, ~cents)
1. You create the VM in the console with tags/labels `managed-by=demo-machines`, `owner`, `expires_at`, firewall limited to your /32.
2. Follow the runbook, time each step, run the demo, forward ports.
3. **Delete the VM and firewall in the console. Verify the project is empty.**

**Exit:** written step list + measured total time. Hand the notes to the agent.
**Sign-off:** "GO Phase 1a" with the runbook filled in.

---

## Phase 1a — Terraform on Hetzner

Sub-phases are individually gated so you learn each Terraform concept before the next.

### 1a.0 Repo scaffolding
- Agent: `Makefile` skeleton (prints underlying `terraform` command), `.terraform-version`, `profiles/demo-no-llm.example.tfvars`, `.gitignore` check for `state/`, `*.tfvars`, gitleaks config, `package.json` + strict `tsconfig` stub (so CI commands exist), CI workflow running fmt/validate/tflint/scan/gitleaks.
- **DRY gate:** `make help`, `gitleaks detect --no-banner`, `terraform fmt -check -recursive`. Confirm no secrets/state in the tree.

### 1a.1 Variables and provider only
- Agent: `terraform/hetzner/{versions.tf,variables.tf,outputs.tf}` with pinned versions, the README contract variables, `validation` blocks (`allowed_cidrs` must not contain `0.0.0.0/0` or `::/0`, `ttl_hours` > 0, `size` in curated set). No resources.
- **DRY gate:** `terraform -chdir=terraform/hetzner init -backend=false && validate`; intentionally pass `allowed_cidrs=["0.0.0.0/0"]` with a throwaway var file and confirm validation **rejects** it.
- Learning: variables, tfvars, validation.

### 1a.2 Firewall + SSH key + server (no cloud-init yet)
- Agent: resources for SSH key, firewall (22 from `allowed_cidrs` only), server with labels `managed-by`, `owner`, `expires_at` (computed from `ttl_hours`; explain `timestamp()`/`timeadd()` and the drift/replacement side effect), outputs: IP, SSH user, instance id, `expires_at`. Curated `small`/`medium` size map. Local state through `-backend-config`.
- **DRY gate:** `fmt`, `validate`, `tflint`, trivy/checkov. Agent explains every resource in the file in a short walkthrough.
- **Human DRY (credentials):** `make plan PROVIDER=hetzner PROFILE=demo-no-llm`. Read the plan line by line; you must be able to explain it (success criterion).
- **LIVE 💰:** you run `make up`; SSH in manually; confirm labels in console; run `make down`; confirm the console shows nothing and `state list` is empty.

### 1a.3 cloud-init via `templatefile`
- Agent: `bootstrap/cloud-init.yaml.tftpl` (calls or embeds `bootstrap.sh`; no secrets), wiring to `user_data`. Idempotent `bootstrap.sh` (Docker + Compose, clone repo using agent forwarding, optional `compose up`).
- **DRY gate:** `validate`; render the template locally (`terraform console` or a test output) and check **no secret** appears; run `shellcheck bootstrap/bootstrap.sh` if installed.
- **LIVE 💰:** `make up`; time to ready; run `bootstrap.sh` a **second time** over SSH to prove idempotency; `docker ps`; `make down`.

### 1a.4 Tooling: ssh-config, `open`, `status`, `allow-my-ip`
- Agent: `src/ssh-config` (TypeScript, strict, unit tests for rendering with fixtures), `make open/status/allow-my-ip/down`. `allow-my-ip` fills a detected /32 only.
- **DRY gate:** `npm run typecheck && lint && test`; render an ssh-config entry from a fixture and inspect it.
- **LIVE 💰:** full `up → open → demo → allow-my-ip (observe in-place update in plan) → down`, three rehearsals.

**Exit criteria (human checks):** 3 rehearsals ≤ 10 min each; `down` leaves nothing; you can explain every resource and every line of `plan`.
**Sign-off:** "GO Phase 1b".

---

## Phase 1b — AWS

- 1b.1 Agent: `terraform/aws` variables/outputs identical to Hetzner (document any difference); AMI data source (Ubuntu 24.04); **DRY gate:** validate + plan-free review.
- 1b.2 Agent: security group (SSH from `allowed_cidrs`), key pair, instance, EBS sizing, default tags via provider `default_tags` plus resource tags, IAM instance profile (minimal; none unless needed). **DRY gate:** fmt/validate/tflint/scan. **Human DRY:** `make plan PROVIDER=aws`.
- 1b.3 Agent: reuse the same cloud-init/bootstrap (no divergent copy).
- **LIVE 💰:** `up → open → down` ×3. Note the public IPv4 charge and verify that EBS volume and IP are gone after `down`.
- **Exit:** same as 1a. Record lessons (quota errors, AMI differences) in the README Troubleshooting table.
- **Sign-off:** "GO Phase 2". (**GPU is still forbidden.**)

---

## Phase 2 — Reaper

- 2.1 Agent: `src/reaper` expiry logic with a **fake clock**; schema-validated provider responses; fixtures recorded with a date. Tests prove untagged and non-expired resources are never selected.
- 2.2 Agent: Hetzner + AWS adapters (list only). **DRY gate:** `npm test`; human runs `npm run reaper -- --dry-run` against a live account with a machine running (agent prints what *would* be deleted — verify the list is correct, and that unrelated resources aren't listed).
- 2.3 Agent: delete behind explicit `--delete` flag; dry-run default; alert on anything older than N hours.
- 2.4 Agent: scheduling (CI workflow with list/delete-only tokens in repo secrets, laptop cron fallback) — you create the tokens and secrets yourself.
- **LIVE 💰:** 
  1. `make up` with `ttl_hours=1`-ish (a short TTL).
  2. Reaper dry-run: not listed before expiry; listed after.
  3. Reaper `--delete` (run by you). Confirm the VM and attached resources vanish on **both** providers.
  4. Let the scheduled job do it once unattended.
  5. Orphan test: delete `state/` copy of a throwaway profile, confirm the reaper still finds the VM.
- **Exit:** forgotten VM expires on its own on both providers. **This unlocks GPU work.**
- **Sign-off:** "GO Phase 3".

---

## Phase 3 — Cost report

- 3.1 Agent: money model (integer minor units or decimal library, currency, tax-inclusive flag), billing granularity per provider with tests (AWS per-second with minimum; Hetzner hourly capped by monthly), usage-plan YAML parser + tests.
- 3.2 Agent: `pricing/overrides.yaml` (value, date, source URL), report generator with data age + override flags, recorded fixtures. **DRY gate:** `npm test`; generate a report from fixtures only and inspect `reports/*.md/.csv`.
- 3.3 Agent: Hetzner fetcher (verify token requirement — mark `UNVERIFIED` otherwise), AWS Price List fetcher (regional endpoint caveat, no bulk files). **Human LIVE (no cost):** `npm run prices:fetch`; sanity-check against the provider consoles; the agent does not call live APIs in tests.
- 3.4 `npm run cost -- --plan pricing/usage-plans/q4.yaml`; includes the "forgot 72h" line.
- **LIVE 💰 (reconcile):** after a real session, you compare estimate vs bill in `reports/accuracy.md`. Error > 20% twice → fix the model.
- **Exit:** report for a real planned period; reconciled against a real bill (±15% target).
- **Sign-off:** "GO Phase 4".

---

## Phase 4 — GCP, then Linode

One provider at a time; each repeats the 1a pattern: variables → resources → cloud-init → plan → live ×3 → pricing fetcher → reaper adapter.

- 4.1 **GCP:** verify the GCP compute SKU composition (per-vCPU/GB-RAM + disk + IP; external IP billing is `UNVERIFIED` until checked). **DRY:** validate/tflint/scan; **human plan**; **LIVE 💰** ×3; pricing composed and tested; reaper adapter tested.
- 4.2 **Linode:** verify cloud-init support per region/image first (`UNVERIFIED`); fall back to `bootstrap.sh` over SSH if absent. Hourly rounding up tested. Same gates.
- **Exit:** same as 1a plus pricing and reaper per provider. **Sign-off after each provider.**

---

## Phase 5 — LLM / GPU profile (only after Phase 2 exit)

- 5.1 Agent: `gpu-24`/`gpu-48` size maps per provider (hand-curated; check CPU/RAM sufficiency for 20 containers + LLM). **Hetzner excluded.** DRY gate: validate/plan review; confirm TTL ≤ short default and reaper is scheduled.
- 5.2 Agent: bootstrap extension (NVIDIA driver + container toolkit, Ollama/vLLM, model prefetch during prep, never on demo day; data on the persistent root volume, not instance-store NVMe).
- 5.3 **Human checks first:** AWS GPU quota granted; budget alert in place; calendar alarm set.
- **LIVE 💰💰 (highest cost):** one provider first, with a short TTL; cold start to model serving measured; `nvidia-smi` and a sample inference; `down`; verify with the reaper dry-run that nothing is left. Surface quota errors clearly — no retry loops.
- **Exit:** cold start to serving within an agreed, measured time.
- **Sign-off:** "GO Phase 6" or stop.

---

## Phase 6 — Only if a real pain exists

Each item needs a written justification first (brief §3 and §7.3). Candidates: Tailscale (opt-in only), pause/resume with explicit cost semantics per provider, remote-state migration exercise, Ansible. Agent stops and asks before starting any of them.

---

## Gate checklist (copy per phase)

```
Phase: ____
[ ] Agent steps complete; agent listed what it ran and what it could NOT verify (UNVERIFIED)
[ ] DRY gate passed (typecheck/lint/test/fmt/validate/tflint/scan/gitleaks)
[ ] LIVE gate run by human; cleanup verified (console empty / reaper dry-run clean)
[ ] No secrets or state in git (gitleaks clean)
[ ] README/brief/AGENTS updated if the interface or a decision changed
[ ] Exit criteria met
[ ] Human sign-off: GO / CHANGES: ______
```

## Stop-and-ask triggers (from AGENTS.md)

The agent stops and asks if a change affects billing, touches credentials, widens network exposure, deletes resources, puts Tailscale or a tunnel on the default path, or the docs contradict each other.
