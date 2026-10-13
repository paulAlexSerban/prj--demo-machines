# Demo Machines — Gated Implementation Plan

Derived from `[00--project-brief.md](00--project-brief.md)` §10, `[README.md](../README.md)` and `[AGENTS.md](../AGENTS.md)`. Nothing is built yet.

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



## Phase −1 — Prerequisites (human only, before any code)

Providers are AWS and GCP. Brief §12 already records the policy, region, venue, demo-file, reaper, and sandbox decisions.


| #    | Human action                                                                                                                                                                                                                                                    | Output                                            |
| ---- | --------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- | ------------------------------------------------- |
| −1.1 | Create a **sandbox AWS account** and a **sandbox GCP project**, separate from anything else you run                                                                                                                                                             | Accounts exist, nothing running                   |
| −1.2 | Set **budget alerts** (~$20) on each                                                                                                                                                                                                                            | Alert visible in each console                     |
| −1.3 | Create **least-privilege credentials** and store them in your password manager or env, **not** in the repo. AWS: IAM user/role scoped to the EC2/VPC actions this tool uses. GCP: a service account for Compute, plus a Billing Catalog API key later (Phase 3) | Credentials exist; agent never sees them          |
| −1.4 | Pick the cheapest region you will actually demo from (brief §12: price over latency). Use that region on both providers unless GPU stock forces a change                                                                                                        | Region written into the example profile notes     |
| −1.5 | Run `make setup` (`bash scripts/setup.sh` if `make` is not installed yet). It installs pinned Terraform, tflint, trivy, and gitleaks into `/usr/local/bin`, and Node when `.nvmrc` is not already satisfied. Scanner is trivy.                                         | `terraform version` matches `.terraform-version` |
| −1.6 | Request **AWS GPU quota now** (lead time is days). Check **GCP GPU availability** in the chosen region and request quota if it is not already granted. Do not raise either beyond what `gpu-24` / `gpu-48` need                                                 | Requests opened; GPU work still waits for Phase 2 |


**Gate:** you reply "GO Phase 0".

---



## Phase 0 — By hand (baseline)

**Goal:** learn what Terraform replaces; produce a measured baseline.

**Agent steps**

- 0.1 Write `_docs/02--phase0-runbook.md`: a fill-in checklist template (create VM in console, install Docker, clone, run, forward ports, open VS Code) with timing columns. No code.
- 0.2 Draft a first version of `bootstrap/bootstrap.sh` *from your notes only after* you finish the run (so it encodes reality, not guesses).

**Gate: DRY** — none (documentation only).

**Gate: LIVE 💰** (AWS, short session — delete it the same day; the budget alert from phase −1 is already on)

1. You create the VM in the console with tags `managed-by=demo-machines`, `owner`, `expires_at`, security group limited to your /32.
2. Follow the runbook, time each step, run the demo, forward ports.
3. **Terminate the instance. Confirm the EBS volume and any public IP are gone.** The console for that region shows nothing this tool created.

**Exit:** written step list + measured total time. Hand the notes to the agent.
**Sign-off:** "GO Phase 1a" with the runbook filled in.

---



## Phase 1a — Terraform on AWS

AWS is the first provider, so this phase carries the Terraform learning and takes the longest. Sub-phases are individually gated. Use the **default VPC**. If the region has none, stop and ask — don't add a network module in this phase. No instance profile until a later phase actually fetches a secret.

### 1a.0 Repo scaffolding

- Agent: extend the Makefile (it already has `setup`, which prints `bash scripts/setup.sh`) with targets that print the underlying `terraform` command. Add `profiles/demo-no-llm.example.tfvars`, `.gitignore` check for `state/`, `*.tfvars`, gitleaks config, `package.json` + strict `tsconfig` stub (so CI commands exist), CI workflow running fmt/validate/tflint/scan/gitleaks.
- **DRY gate:** `make help`, `gitleaks detect --no-banner`, `terraform fmt -check -recursive`. Confirm no secrets/state in the tree.



### 1a.1 Variables and provider only

- Agent: `terraform/aws/{versions.tf,variables.tf,outputs.tf}` with pinned versions, the README contract variables, `validation` blocks (`allowed_cidrs` must not contain `0.0.0.0/0` or `::/0`, `ttl_hours` > 0, `size` in curated set). No resources.
- **DRY gate:** `terraform -chdir=terraform/aws init -backend=false && validate`; intentionally pass `allowed_cidrs=["0.0.0.0/0"]` with a throwaway var file and confirm validation **rejects** it.
- Learning: variables, tfvars, validation.



### 1a.2 Security group + key pair + instance (no cloud-init yet)

- Agent: Ubuntu 24.04 AMI data source; security group (22 from `allowed_cidrs` only); key pair; instance with root EBS size; tags `managed-by`, `owner`, `expires_at` (computed from `ttl_hours`; explain `timestamp()`/`timeadd()` and the drift/replacement side effect) via provider `default_tags` plus resource tags. Outputs: IP, SSH user, instance id, `expires_at`. Curated `small`/`medium` size map. Local state through `-backend-config`.
- **DRY gate:** `fmt`, `validate`, `tflint`, trivy/checkov. Agent explains every resource in the file in a short walkthrough.
- **Human DRY (credentials):** `make plan PROVIDER=aws PROFILE=demo-no-llm`. Read the plan line by line; you must be able to explain it (success criterion).
- **LIVE 💰:** you run `make up`; SSH in manually; confirm tags in the console; run `make down`; confirm the instance, EBS volume and public IP are gone and `state list` is empty.



### 1a.3 cloud-init via `templatefile`

- Agent: `bootstrap/cloud-init.yaml.tftpl` (calls or embeds `bootstrap.sh`; no secrets), wiring to `user_data`. Idempotent `bootstrap.sh` (Docker + Compose, clone repo using agent forwarding, optional `compose up`).
- **DRY gate:** `validate`; render the template locally (`terraform console` or a test output) and check **no secret** appears; run `shellcheck bootstrap/bootstrap.sh` if installed.
- **LIVE 💰:** `make up`; time to ready; run `bootstrap.sh` a **second time** over SSH to prove idempotency; `docker ps`; `make down`.



### 1a.4 Tooling: ssh-config, `open`, `status`, `allow-my-ip`

- Agent: `src/ssh-config` (TypeScript, strict, unit tests for rendering with fixtures), `make open/status/allow-my-ip/down`. `allow-my-ip` fills a detected /32 only.
- **DRY gate:** `npm run typecheck && lint && test`; render an ssh-config entry from a fixture and inspect it.
- **LIVE 💰:** full `up → open → demo → allow-my-ip (observe in-place update in plan) → down`, three rehearsals. After each `down`, confirm the volume and public IP are gone.

**Exit criteria (human checks):** 3 rehearsals ≤ 10 min each; `down` leaves nothing; you can explain every resource and every line of `plan`.
**Sign-off:** "GO Phase 1b". (**GPU is still forbidden.**)

---



## Phase 1b — GCP

Same variable contract. Use the **default network** and a firewall rule. No service account until a later phase fetches a secret. Reuse the AWS cloud-init and `bootstrap.sh` — no second bootstrap.

- 1b.1 Agent: `terraform/gcp` variables/outputs identical to AWS (document any difference); Ubuntu 24.04 image data source. **DRY gate:** `init -backend=false`, `validate`, tflint, security scan.
- 1b.2 Agent: firewall rule (SSH from `allowed_cidrs` only), instance, boot disk size, labels `managed-by`, `owner`, `expires_at`. **DRY gate:** same as 1b.1. **Human DRY:** `make plan PROVIDER=gcp PROFILE=demo-no-llm`.
- **LIVE 💰:** `up → open → down` ×3. After each `down`, confirm the instance, boot disk and external IP are gone.
- **Exit:** same as 1a. Record lessons (quota, zone stock) in the README Troubleshooting table.
- **Sign-off:** "GO Phase 2". (**GPU is still forbidden.**)

---



## Phase 2 — Reaper

- 2.1 Agent: `src/reaper` expiry logic with a **fake clock**; schema-validated provider responses; fixtures recorded with a date. Tests prove untagged and non-expired resources are never selected.
- 2.2 Agent: AWS and GCP list adapters (tags on AWS, labels on GCP). **DRY gate:** `npm test`; you run `npm run reaper -- --dry-run` against a live account with a machine running. Check the list, and check that unrelated resources are absent.
- 2.3 Agent: delete behind an explicit `--delete` flag; dry-run default; alert on anything older than N hours.
- 2.4 Agent: scheduling as a CI workflow (brief §12). You create the list/delete-only tokens and repo secrets yourself. Laptop cron stays a fallback.
- **LIVE 💰:**
  1. `make up` with a short TTL, once on AWS and once on GCP.
  2. Reaper dry-run: not listed before expiry; listed after.
  3. Reaper `--delete` (run by you). Confirm the VM, disk and public IP vanish on **both** providers.
  4. Let the scheduled job do it once unattended.
  5. Orphan test: remove the `state/` file for a throwaway profile, confirm the reaper still finds the VM.
- **Exit:** a forgotten VM expires on its own on both providers. **This unlocks GPU work.**
- **Sign-off:** "GO Phase 3".

---



## Phase 3 — Cost report

- 3.1 Agent: money model (integer minor units or decimal library, currency, tax-inclusive flag), billing granularity per provider with tests (confirm AWS per-second minimum and GCP granularity from current docs; don't assume they match), usage-plan YAML parser + tests.
- 3.2 Agent: `pricing/overrides.yaml` (value, date, source URL), report generator with data age + override flags, recorded fixtures. **DRY gate:** `npm test`; generate a report from fixtures only and inspect `reports/*.md/.csv`.
- 3.3 Agent: AWS Price List fetcher (regional endpoint caveat, no bulk files). GCP Billing Catalog fetcher that **composes** vCPU + RAM + disk + IP (+ GPU when present). External-IP billing stays `UNVERIFIED` until the fetcher result is checked against the catalog. **Human LIVE (no VM cost):** you create the GCP API key, then run `npm run prices:fetch` and sanity-check both providers against their consoles. Tests never call live APIs.
- 3.4 `npm run cost -- --plan pricing/usage-plans/q4.yaml`; includes the "forgot 72h" line. `pause_between` means a stopped instance: compute off, disk and public IP on.
- **LIVE 💰 (reconcile):** after a real session, you compare estimate vs bill in `reports/accuracy.md`. Error > 20% twice → fix the model.
- **Exit:** report for a real planned period; reconciled against a real bill (±15% target) on at least one session per provider.
- **Sign-off:** "GO Phase 4".

---



## Phase 4 — LLM / GPU profile (only after Phase 2 exit)

- 4.1 Agent: `gpu-24` / `gpu-48` size maps for AWS and GCP (hand-curated; confirm CPU and RAM are enough for 20 containers plus an LLM). **DRY gate:** validate and a credentialed `plan` review; confirm TTL stays short and the reaper is scheduled.
- 4.2 Agent: bootstrap extension (NVIDIA driver + container toolkit, Ollama or vLLM, model prefetch during prep, never on demo day). Model weights go on the persistent root volume. On AWS GPU families, instance-store NVMe is wiped on stop.
- 4.3 **Human checks first:** AWS GPU quota granted; GCP GPU quota and zone stock confirmed; budget alerts on; calendar alarm set for the session.
- **LIVE 💰💰 (highest cost):** one provider first, short TTL. Measure cold start to a served model; `nvidia-smi` and a sample inference; `down`; reaper dry-run shows nothing left (instance, disk, GPU, public IP). Surface quota errors clearly — no retry loops. Repeat on the other provider only after the first is clean.
- **Exit:** cold start to serving within an agreed, measured time.
- **Sign-off:** "GO Phase 5" or stop.

---



## Phase 5 — Only if a real pain exists

Each item needs a written justification first (brief §3 and §7.3). Candidates: Tailscale (opt-in only), pause/resume polish, remote-state migration as an exercise, Ansible. Agent stops and asks before starting any of them.

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