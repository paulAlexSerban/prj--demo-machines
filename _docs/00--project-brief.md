# Demo Machines — Project Brief


|            |                                                                                                                                                         |
| ---------- | ------------------------------------------------------------------------------------------------------------------------------------------------------- |
| **Status** | Draft v0.2 — design only, nothing is built. v0.2: Terraform as learning vehicle, local state, Tailscale as fallback only, hardware-avoidance motivation. Providers: AWS and GCP only |
| **Date**   | 2026-10-13                                                                                                                                              |
| **Owner**  | Paul Serban - [paul.alex.serban@gmail.com](mailto:paul.alex.serban@gmail.com)                                                                           |
| **Tone**   | Deliberately blunt. It is cheaper to hear this now than after three weeks of Terraform.                                                                 |


---



## 1. Summary

A small toolkit that creates **disposable cloud VMs for demos** on AWS and GCP:

- one command to create a VM (Docker installed, repo cloned, ports reachable),
- one command to destroy it, plus automatic expiry as a safety net,
- VS Code Remote-SSH to work on it,
- a script that estimates what a planned period of usage will cost on each provider.

**First concrete use case:** a ~2-hour demo (plus prep) running ~20 containers in parallel, with frontend ports reachable from the laptop, on roughly 8 vCPU / 32 GB RAM / 64–100 GB SSD, no LLM.
**Second use case:** the same, plus a local LLM on a GPU.

**Why this exists (stated goals):**

- Build demos and showcase them in a few easy steps **without buying a powerful desktop or laptop** — rent the machine only for the hours needed.
- **Learn Terraform hands-on** by building something real. This is a deliberate learning project, so the Terraform stays readable and the scope stays small enough to finish.

---



## 2. Honest assessment — read this first



### 2.1 Is this worth building?

**Yes — for the two reasons you've stated, and neither is "cheaper cloud".**

1. **Hardware avoidance.** You don't want to buy a powerful desktop or laptop just to run demos. At your usage, renting wins by a mile: a 6-hour non-GPU session is ~$2 and a GPU session is roughly $7–25 depending on the box. A machine that can run 20 containers *and* a local LLM costs thousands (order of magnitude, not researched), so you'd need hundreds of sessions to break even — and the rented box can be bigger than anything you'd buy. Any modest laptop becomes a thin client.
2. **Learning Terraform on something real.** That makes "just write a shell script" the wrong benchmark: the script is faster, but speed isn't the goal. It does change the advice: keep the scope small enough to **finish**. A finished small project teaches more than an abandoned platform.

**Still true, and unpleasant:**

- Between cloud providers the price differences are cents. Pick providers for learning value, GPU availability and reliability — not price.
- Money only gets scary with **GPU machines** and **forgotten machines**.
- **A remote machine has a failure mode a local one doesn't: the venue's internet.** If the Wi-Fi dies, the demo dies. Keep a fallback (a screen recording of a clean run, a phone hotspot).
- Terraform's sweet spot is long-lived infrastructure; create-use-destroy of one VM is a simple case for it. Fine for learning — just expect it to feel educational, not efficient.
- What you showcase is the demo app; the machine is plumbing. Don't let the plumbing consume the time you need to build the demos.



### 2.2 Where the original idea overreaches


| Idea                                                  | Verdict                                                                                                                                                                                                                                                                                  |
| ----------------------------------------------------- | ---------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| **Kubernetes**                                        | **Don't.** 20 containers on one VM is Docker Compose. k8s adds a control plane to debug during a demo and buys nothing here. Non-goal.                                                                                                                                                   |
| **Ansible**                                           | **Not in v1.** Cloud-init plus one idempotent bootstrap script covers "install Docker, clone repo, start stack" on a single VM. Add Ansible only if that script turns into a swamp (several host roles, real config drift).                                                              |
| **A third provider**                                  | **Don't.** The set is AWS and GCP. Terraform does not make them interchangeable; you write two roots. Only the *input contract* (variable names and meanings) is shared. Prove that contract on AWS, then repeat it on GCP. |
| **"Give the machine access to restricted resources"** | **This is the dangerous part, not a feature.** See §7.                                                                                                                                                                                                                                   |
| **Generic "cpu/ram → instance type" matcher**         | Rabbit hole. Hand-curate 3–6 named sizes per provider.                                                                                                                                                                                                                                   |
| **Tailscale**                                         | **Fallback, not default.** SSH + port forwarding covers the common case. Add Tailscale only when a concrete need shows up (§7.3).                                                                                                                                                        |
| **Cost report**                                       | Worth it, but it is mostly arithmetic once you have unit prices, and *getting reliable unit prices is the hard part* (§8).                                                                                                                                                               |




### 2.3 Ranked risks

1. **Forgotten machine.** A ~$3/hr GPU box left running over a long weekend is ≈ $216. Stopping the instance stops compute billing on AWS and GCP. The disk and the public IP keep billing until they are deleted.
2. **Credential leakage.** Tokens end up in Terraform state, user-data, shell history, or inside a container you started on the box.
3. **Policy / legal.** If the repo, data or credentials belong to an employer or client, putting them on a personal cloud account may violate their rules. This tool makes that very easy to do by accident. Check before you use it for anything that isn't yours.
4. **Scope creep.** This is a ~2-week project that wants to become a 3-month platform.
5. **First run on demo day.** GPU quotas (AWS starts at zero; GCP availability varies by region), zone stock-outs and price changes all happen at the worst moment. **Rehearse a full provision at least 2 days before every demo** and keep a fallback (laptop, or the other provider).
6. **Wrong or stale prices.** See §8.
7. **Venue internet.** A remote demo needs a working connection. Have a fallback: a recording of a clean run, a phone hotspot, ideally a cut-down local version.
8. **Local state loss.** Lose the state file and Terraform forgets machines that are still billing. See §6.4; the tag-based reaper is the backstop.
9. **Learning-curve slippage.** Every estimate in §10 is optimistic while you're learning Terraform. The first provider takes longest; that's expected, not failure.



### 2.4 Alternatives to know about

- **Do it by hand first** (Phase 0): create the VM in the console or CLI, install Docker, clone, run, forward ports. It's the fastest way to learn what Terraform is replacing, and it gives you the baseline to beat.
- **DevPod** (open source; provisions VMs on several clouds, auto-stops idle machines, VS Code integration; can clone a repo and use a default image without touching it). Because Terraform learning is a goal you're building anyway, but keep it in mind as a **demo-day fallback and a reference design**. Verify its current maintenance status and whether it handles "20 containers via the host Docker daemon + exposed ports" cleanly.
- **A plain CLI script** is the pragmatic fallback if the project stalls. Never end up in a position where a broken Terraform setup is the only way to run a demo.

---



## 3. Goals and non-goals



### Goals

- **G1** One command: `provider + profile → SSH-able VM` with Docker (and NVIDIA toolkit for GPU profiles), repo cloned, optionally stack started, in ≈ 10 minutes.
- **G2** One command to destroy, and a way to verify nothing billable is left.
- **G3** All variable parameters live in config files (profiles), not in code.
- **G4** VS Code Remote-SSH works through a generated SSH config; app ports are reachable via SSH port forwarding by default.
- **G5** Every machine has a TTL, enforced *outside* the VM.
- **G6** A cost report for a planned period across providers, with stated accuracy and data freshness.
- **G7** Secrets are never in git, never in plaintext user-data, and kept out of Terraform state wherever we control it.
- **G8** Showcase in few steps: `make up` → `make open` → demo → `make down`.
- **G9** Hands-on Terraform learning: the HCL stays simple, explicit and explainable line by line.



### Non-goals

Kubernetes · Ansible (v1) · multi-user/team features · remote state backends (state is deliberately local) · web UI · production workloads · HA / autoscaling · Windows VMs · a third provider · automated cost *optimization* (the tool reports, you decide) · managing the demo application itself.

---



## 4. Profiles (use cases)


| Profile       | Spec                                                                                                                                        | Notes                                                                                                                                                                                                                            |
| ------------- | ------------------------------------------------------------------------------------------------------------------------------------------- | -------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| `demo-no-llm` | 8 vCPU / 32 GB RAM / **100 GB** SSD, Ubuntu 24.04, Docker + Compose                                                                         | 64 GB is tight for ~20 images plus build cache — budget 100 GB; it costs pennies. Frontend ports via SSH forwarding.                                                                                                             |
| `demo-llm`    | GPU with 24 GB VRAM (7–14B models) or 48 GB (≈30B quantized), ≥ 64 GB RAM, ≥ 200 GB disk, NVIDIA driver + container toolkit, Ollama or vLLM | Models are pre-pulled during prep, **never on demo day**. Providers: AWS and GCP. Verify GPU availability per region before relying on a size. |




### Demos vs machines

A **profile** describes a machine (provider, size, disk, TTL). A **demo** is what runs on it (repo, ref, compose file, ports to forward, a health-check URL). In v1 both live in one tfvars file per demo. If you end up with more than ~3 demos, split them into a small manifest per demo so one machine profile can serve many demos.

### Reference prices (rough planning snapshot, Oct 2026)

> These come from third-party aggregator pages that **disagreed with each other and are partly months old**. They exist only to size the problem. Replacing this table with live data is the whole point of the pricing tool (§8). AWS non-GPU instances were not researched.


| Box                                               | Approx. price                                                                              |
| ------------------------------------------------- | ------------------------------------------------------------------------------------------ |
| GCP `e2-standard-8` (8 vCPU / 32 GB)              | ~$0.27–0.30 / hr depending on region                                                       |
| GCP `g2-standard-8` (8 vCPU / 32 GB / L4 24 GB)   | ~$0.85 / hr (us-central1)                                                                  |
| AWS `g6.4xlarge` (16 vCPU / 64 GB / L4 24 GB)     | ~$1.32 / hr (us-east-1)                                                                    |
| AWS `g6e.4xlarge` (16 vCPU / 128 GB / L40S 48 GB) | ~$3.00 / hr (us-east-1)                                                                    |


Confirm the curated `gpu-24` / `gpu-48` map against current regional availability before use. AWS non-GPU prices are still not in this table.

---



## 5. Requirements



### Functional


| ID  | Priority | Requirement                                                                                                     |
| --- | -------- | --------------------------------------------------------------------------------------------------------------- |
| F1  | MUST     | Create a VM from `(provider, profile)`.                                                                         |
| F2  | MUST     | Destroy it and confirm no tagged resources remain.                                                              |
| F3  | MUST     | Every resource is tagged with `managed-by`, `owner`, `expires_at`; a reaper deletes expired resources (§9).     |
| F4  | MUST     | Generate an SSH config entry usable by VS Code Remote-SSH (including agent forwarding when configured).         |
| F5  | MUST     | Bootstrap: Docker + Compose (+ NVIDIA toolkit for GPU), clone the repo (given ref), optionally `compose up`.    |
| F6  | MUST     | Inbound access restricted to explicit CIDRs or a private network. No app ports open to the internet by default. |
| F7  | SHOULD   | `pause` / `resume` with *explicit* cost semantics per provider (§6).                                            |
| F8  | SHOULD   | `status`: what is running, since when, TTL remaining, cost so far.                                              |
| F9  | MUST     | Cost report from a usage plan (§8).                                                                             |
| F10 | COULD    | Tailscale — fallback only (§7.3), for private access to the VM or to internal resources.                        |
| F11 | SHOULD   | `open`: one command that writes the SSH config, starts port forwards and opens VS Code on the repo.             |




### Non-functional

- Idempotent and rehearsable: `plan` shows everything before anything is created.
- Pinned versions for Terraform, providers and tooling.
- No secrets in the repository, ever; a secret scanner runs in CI.
- Works from macOS/Linux shells.
- Terraform stays readable: simple, explicit HCL over clever abstractions; the Makefile prints the underlying `terraform` command it runs.

---



## 6. Architecture and key decisions



### 6.1 Layout (proposed)

```
demo-machines/
├── README.md
├── AGENTS.md
├── _docs/00--project-brief.md
├── _docs/01--implementation-plan.md
├── Makefile                      # thin wrapper: up / down / pause / resume / status / ssh-config
├── profiles/                     # *.example.tfvars committed; real *.tfvars gitignored
├── terraform/
│   ├── aws/                      # one root per provider, same variable names
│   ├── gcp/
│   └── modules/                  # only what is genuinely shared (e.g. cloud-init rendering)
├── bootstrap/
│   ├── cloud-init.yaml.tftpl
│   └── bootstrap.sh              # idempotent; runnable standalone over SSH
├── src/
│   ├── pricing/                  # fetchers, normaliser, report
│   ├── reaper/                   # list/delete expired tagged resources across providers
│   └── ssh-config/               # writes ~/.ssh/config.d/demo-machines
├── pricing/usage-plans/          # YAML usage plans
└── reports/                      # generated, gitignored
```



### 6.2 Decisions


| Decision          | Choice                                                                         | Status      | Why                                                                                                                                                                                                 |
| ----------------- | ------------------------------------------------------------------------------ | ----------- | --------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| IaC               | Terraform only (no OpenTofu)                                                   | Decided     | It's also the learning vehicle: the point is hands-on Terraform experience.                                                                                                                         |
| Root modules      | **One root per provider**, identical variable names                            | Decided     | A single root with both provider blocks needs credentials for both on every run.                                                                                                                    |
| Sizing            | Hand-curated named sizes per provider (`small`, `medium`, `gpu-24`, `gpu-48`)  | Recommended | Auto-matching specs to instance types is a time sink.                                                                                                                                               |
| First-boot config | cloud-init user-data, falling back to running `bootstrap.sh` over SSH          | Recommended | Ubuntu cloud-init on AWS and GCP. One shared `bootstrap.sh`. If cloud-init fails on an image, run that same script over SSH.                                                                        |
| State             | **Local**, one file per provider+profile under `state/` (gitignored, mode 600) | Decided     | Single user, simplest to learn from. Trade-offs in §6.4.                                                                                                                                            |
| Tooling language  | TypeScript (Node 22) for pricing + reaper                                      | Recommended | Author's primary stack; both providers are plain REST/SDK. Python is equally valid — pick one, don't support both.                                                                                  |
| Ansible / k8s     | Out of scope                                                                   | Decided     | See §2.2.                                                                                                                                                                                           |
| Providers         | **AWS and GCP only**                                                           | Decided     | Hetzner and Linode are out. A third provider is a non-goal.                                                                                                                                         |
| Provider order    | AWS → GCP                                                                      | Decided     | AWS first: GPU quota has lead time, and the variable contract is designed against security groups, AMI lookup and IAM. GCP repeats that contract. Composed GCP pricing belongs in the cost phase.   |




### 6.3 Lifecycle semantics — do not hide the differences


| Provider | Stopped VM billed?                                         | `pause` implementation                               | Notes                                                                                 |
| -------- | ---------------------------------------------------------- | ---------------------------------------------------- | ------------------------------------------------------------------------------------- |
| AWS      | Compute: no. EBS volume (and any public/Elastic IPv4): yes | Stop instance                                        | Public IPv4 is billed hourly; IP changes on restart unless you pay for an Elastic IP. |
| GCP      | Compute: no. Persistent disk (and reserved IPs): yes       | Stop instance                                        | Verify external-IP charges.                                                           |


`pause` stops the instance on both. Compute billing stops; the disk and the public IP do not. The CLI must print that every time.

### 6.4 Local state — a deliberate trade-off

Local state is fine for one user and is the best way to learn: you can open the file, run `terraform state list` and `terraform state show`, and see exactly what Terraform believes exists. What you're accepting:

- **No backup.** Disk dies or the folder is deleted → Terraform forgets machines that still exist and bill. Mitigations: the tag-based reaper works without state; copy `state/` to an encrypted location after each `up`/`down`.
- **State contains secrets** (anything sensitive that passed through Terraform, generated keys). `state/` is gitignored, mode 600, on an encrypted disk; never paste it into chats or issues.
- **One state file per provider+profile** (`state/<provider>-<profile>.tfstate`), passed via backend config by the Makefile, so profiles never overwrite each other. Workspaces are the alternative; separate files are easier to reason about while learning.
- **It lives on one computer.** Using a second laptop means copying the file. Migrating to a remote backend later is a good learning exercise (Phase 5, optional) — not v1.
- Solo use makes locking a non-issue; just don't run two `terraform` commands against the same state at once.

---



## 7. Access to restricted resources

This is where the project can hurt you. Treat it as a security design, not a convenience feature.

### 7.1 Patterns, in order of preference


| Need                        | Preferred approach                                                                                                                                                                                                            | Avoid                                                                                    |
| --------------------------- | ----------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- | ---------------------------------------------------------------------------------------- |
| Private git repo            | **SSH agent forwarding** from your laptop (no secret lands on the VM). Fallback: fine-grained, read-only PAT, expiry ≤ 7 days, injected over SSH at bootstrap.                                                                | Deploy keys (needs repo admin — you said you don't have it), PAT in user-data or tfvars. |
| Private container registry  | Short-lived token piped to `docker login --password-stdin` over SSH at runtime.                                                                                                                                               | Tokens in compose files or image layers.                                                 |
| App secrets / config        | **AWS:** instance role + SSM Parameter Store / Secrets Manager. **GCP:** attached service account + Secret Manager.                                                                                                      | `.env` committed anywhere; secrets as Terraform variables.                               |
| Internal / private services | If simpler options (§7.3) don't fit, Tailscale with an **ephemeral, tagged, pre-authorized** key and an ACL that limits the node to specific hosts/ports.                                                                     | Opening corporate services to the internet; long-lived VPN credentials on the VM.        |
| Terraform state             | Treat as a secret: local `state/` dir, gitignored, mode 600, disk encryption on, encrypted off-machine backup.                                                                                                                | Committing state; pasting it into chats or issues.                                       |




### 7.2 Hard truths

- `sensitive = true` hides values in terminal output. **It does not keep them out of the state file.**
- User-data is readable from the instance metadata service and, on most providers, from the console/API.
- Anything running on the VM — including every container in the demo stack — can read what the VM can read. Give it the minimum, for the minimum time, and revoke afterwards.
- Both providers give the VM an identity (AWS instance role, GCP service account), so app secrets are fetched at runtime and stay out of user-data.
- **Policy check:** if the repo, data or credentials are an employer's or client's, confirm that running them on a personal cloud account is allowed *before* the first `make up`.



### 7.3 Reaching the demo: easiest option first


| Step                                   | Use when                                                                                                                                                    | How                                                                                                               | Cost of complexity                                                                        |
| -------------------------------------- | ----------------------------------------------------------------------------------------------------------------------------------------------------------- | ----------------------------------------------------------------------------------------------------------------- | ----------------------------------------------------------------------------------------- |
| 1. SSH + port forwarding (**default**) | You're the only viewer, on your own laptop                                                                                                                  | `allowed_cidrs` = your public IP /32; `make open` forwards the demo ports to `localhost`                          | Nothing public, no extra accounts                                                         |
| 2. Refresh the allowed IP              | Your IP changed (new venue, new Wi-Fi)                                                                                                                      | `make allow-my-ip` updates the firewall rule — a one-variable `terraform apply` (a nice in-place-update exercise) | None                                                                                      |
| 3. Tailscale                           | You must reach private/internal resources from the VM, another device needs private access (tablet, second screen), or your IP changes too often for step 2 | Ephemeral, tagged, pre-authorized key + tight ACL; off by default                                                 | One more account, one more secret, one more failure mode (verify current free-tier terms) |
| 4. Public URL (e.g. Cloudflare Tunnel) | The audience must open the demo themselves                                                                                                                  | Tunnel with access control in front, short-lived                                                                  | Public exposure of your demo; verify terms and setup                                      |


**Rule:** don't jump to 3 or 4 because they're fun. The likeliest trigger for step 3 is a constantly changing IP; try step 2 first.

---



## 8. Pricing and cost report



### 8.1 Data sources (to be verified during implementation)


| Provider | Source                                                                                                               | Catch                                                                                                                                                                                              |
| -------- | -------------------------------------------------------------------------------------------------------------------- | -------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| AWS      | Price List API (`pricing:GetProducts`, filtered by instance type/region/OS); `ec2:DescribeSpotPriceHistory` for spot | Needs credentials; the pricing API is served from only a few regions regardless of which region you price; bulk offer files are huge — don't use them.                                             |
| GCP      | Cloud Billing Catalog API (Compute Engine service)                                                                   | Prices are per vCPU-hour and per GB-RAM-hour by machine family, plus separate SKUs for disks, GPUs, IPs — **instance price must be composed**. Needs an API key. Budget a full day for this alone. |


**Rules:**

- **Never scrape third-party price sites or marketing pages.** During planning, aggregators contradicted each other and were months stale.
- If a provider API can't give a number, use `pricing/overrides.yaml` with **value, date and source URL**, and show every override in the report.
- Cache fetched prices with a timestamp; the report prints data age and warns above a threshold (default 14 days).



### 8.2 What the estimate will and won't be

- **Target accuracy:** ±15% for compute + disk + IP over the stated hours.
- **Not promised:** egress, taxes/VAT, FX, free-tier or credits, support plans.
- Model billing granularity per provider, with a test. Confirm AWS's per-second minimum and GCP's granularity from current docs when the fetchers are written.
- **Reconcile after real use:** compare estimate vs actual bill and log it in `reports/accuracy.md`. If error exceeds 20% twice, fix the model rather than trusting it.



### 8.3 Usage plan (input)

```yaml
period: 2026-11-01..2027-01-31
scenarios:
  - name: monthly-demo
    profile: demo-no-llm
    sessions: 3
    hours_per_session: 6          # prep + demo
    lifecycle: destroy_after      # destroy_after | pause_between
    providers: [aws, gcp]
  - name: llm-demo
    profile: demo-llm
    sessions: 1
    hours_per_session: 8
    lifecycle: destroy_after
    providers: [aws, gcp]
include: { disk: true, public_ip: true, snapshots: true, vat: false }
risk_scenarios: [forgot_72h]      # what a forgotten machine would cost
```



### 8.4 Report (output)

`reports/<date>-cost.md` and `.csv`, containing: per-provider totals; per-line breakdown (compute, disk, IP, snapshot); `destroy_after` vs `pause_between` comparison; **the "forgot it for 72h" line for each provider**; price-data timestamps; warnings for stale or overridden prices.

---



## 9. Cost safety (non-negotiable)

- Every resource carries `managed-by=demo-machines`, `owner`, `expires_at` (UTC ISO). AWS tags and GCP labels both carry these three keys.
- **Reaper:** a scheduled job *outside* the VM lists tagged resources across providers and destroys expired ones, and alerts on anything older than N hours. A VM shutting *itself* down is **not enough**: compute billing stops, but the instance, disk and public IP stay until something deletes them.
- Where does the reaper run? Laptop cron only works while the laptop is on. Recommended: a scheduled CI workflow (e.g. GitHub Actions) with list/delete-only tokens in repo secrets; laptop cron as a fallback. **Open decision.**
- Default TTL 12 h; extending it is an explicit action.
- **No GPU machines until the reaper works.** Until then: budget alert plus a calendar alarm for every running machine.
- Budget alerts with low thresholds (e.g. $20) on every account/project.
- Dedicated sandbox account/project per provider; least-privilege credentials for Terraform.
- Don't raise GPU quotas beyond what you need — the quota is a seatbelt.
- `make status` shows what's running and its hourly cost.

---



## 10. Phases and estimates

Gut estimates for part-time work, **assuming you're learning Terraform as you go**: the first provider will take longest.


| Phase                         | Scope                                                                                                                                                                                    | Est.                                         | Exit criteria                                                                                          |
| ----------------------------- | ---------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- | -------------------------------------------- | ------------------------------------------------------------------------------------------------------ |
| **0 — By hand**           | Create the VM manually (console/CLI) on AWS, install Docker, clone the repo, run the demo, forward ports, open VS Code. Time it; write down every step.                                                          | ½–1 day   | Written step list; measured baseline for Terraform to beat.                                                                     |
| **1a — Terraform on AWS** | Variable contract, AMI data source, security group, key pair, instance, EBS sizing, tags, `templatefile` cloud-init, local state per profile, `up/down/status/open`. Default VPC. Request GPU quota now. | 4–5 days  | 3 rehearsals ≤ 10 min; `down` leaves nothing (instance, volume, public IP); you can explain every resource and every line of `plan`. |
| **1b — GCP**              | Same variable contract: image lookup, firewall rule, instance, boot disk, labels. Reuse the AWS cloud-init.                                                                                                         | 2–3 days  | Same criteria as 1a.                                                                                                                 |
| **2 — Reaper**            | Tag/label reaper for AWS + GCP, dry-run default, scheduled outside the VM.                                                                                                                                        | 1–2 days  | A forgotten VM expires on its own on both providers. **Gate: no GPU machines before this.**                                          |
| **3 — Cost report**       | Fetchers (AWS Price List, GCP Billing Catalog), usage plan, report, accuracy log. GCP pricing is the slow part.                                                                                                   | 3–4 days  | Report for a real planned period; reconciled against a real bill.                                                                    |
| **4 — LLM profile**       | GPU sizes on AWS and GCP, driver/toolkit bootstrap, model prefetch, quota notes.                                                                                                                                  | 2–3 days  | Cold start to serving a model within an agreed, measured time.                                                                       |
| **5 — Only if needed**    | Tailscale, pause/resume polish, remote-state migration as an exercise, Ansible only with a concrete justification.                                                                                                | —         | A real pain from earlier phases.                                                                                                      |




### 10.1 Terraform learning map


| Concept                              | Where you'll meet it                                                    |
| ------------------------------------ | ----------------------------------------------------------------------- |
| Variables, tfvars, validation blocks | Profiles                                                                |
| Outputs                              | `status`, ssh-config (IP, user, `expires_at`)                           |
| Data sources                         | AWS AMI lookup; GCP image and machine-type lookup                       |
| `templatefile`                       | cloud-init                                                              |
| Dependencies, `depends_on`           | Security group / firewall rule ↔ instance                               |
| In-place update vs replacement       | `make allow-my-ip` (update); `terraform apply -replace=…` (rebuild)     |
| `terraform import`                   | Adopt the hand-built Phase 0 VM (optional exercise)                     |
| State commands                       | `state list/show` — look inside, and notice what secrets it holds       |
| `moved` blocks, refactoring          | When (if) a shared module is extracted                                  |
| Provisioners                         | Read about them, then understand why they're discouraged and avoid them |
| Remote backends                      | Optional Phase 5 migration                                              |


---



## 11. Success criteria

- From nothing to a running stack in ≤ 10 minutes, three times in a row, on each supported provider.
- `down` leaves zero tagged resources (verified by a reaper dry-run).
- A forgotten machine expires on its own within TTL + one reaper interval, on every provider.
- Estimate vs actual bill within 15% on at least one real session per provider.
- No secrets in git history or user-data; the local state file is gitignored and mode 600. Verified with a scanner and a manual state inspection.
- You can explain every Terraform resource and every line of a `plan` for a full run — if you can't, the learning goal isn't met even if the demo works.
- A demo can be shown with ≤ 3 manual steps after provisioning (`up`, `open`, `down`).

---



## 12. Decisions

- **Decided (v0.2):** Terraform only · local state · Tailscale only as a fallback (§7.3).
- **Decided:** Providers are **AWS and GCP only**, in that order. Hetzner and Linode are out. A third provider is a non-goal.
- **Whose repo, data and credentials are these?** — and is running them on a personal account permitted? - yes, it is my personal account.
- **Regions** — latency to the venue/audience vs price. - price is more important for now - low as possible.
- **Venue fallback plan** — what you do if the internet fails mid-demo (recording, hotspot, local lite version). - recording is the best option for now - try to run locally first.
- **How demos are defined** — profile + demo in one tfvars file (v1) vs a separate manifest once there are more than ~3 demos. - one tfvars file for now - it is simple and easy to understand.
- **Where the reaper runs** — recommendation: a scheduled CI workflow with list/delete-only tokens; laptop cron as a fallback. - scheduled CI workflow is the best option for now - it is simple and easy to understand.
- **Personal vs separate sandbox accounts/projects** — recommendation: separate, with budget alerts, before the first `up`. - separate is the best option for now - it is simple and easy to understand.


## 13. Unverified assumptions (check before relying on them)

- AWS pricing API regional endpoints; GCP Compute Engine SKU structure and billing granularity.
- DevPod's current maintenance status, and whether it covers this demo shape on AWS and GCP.
- GPU availability per region on GCP, and AWS GPU quota lead time.
- External-IP billing details on GCP.
- Tailscale's current free-tier limits and Cloudflare Tunnel's terms.
- Exact `terraform init -backend-config` usage for per-profile local state paths (check current docs).

