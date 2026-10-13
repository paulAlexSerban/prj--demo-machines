# prj--demo-machines

Spin up **disposable cloud VMs for demos** on AWS or GCP, connect with VS Code, and know roughly what it will cost before you do it.

The point: **build and showcase demos without owning a powerful desktop or laptop** — rent the machine only for the hours you need. It's also a hands-on **Terraform learning project**.

> ## ⚠️ Status: design only
>
> Nothing described below exists yet. This README is the **target interface**; it's written first so the tool gets built to a spec instead of drifting. Each section is marked with the phase that delivers it (see [`_docs/00--project-brief.md`](_docs/00--project-brief.md)). Don't trust a command until its phase is done.



## Read this before using it

- **Why it exists:** renting a machine for a few hours is far cheaper than buying hardware strong enough for 20 containers (and a local LLM), and you learn Terraform on a real project. Between cloud providers the price differences are cents (a 6-hour 8 vCPU / 32 GB demo is about $2); the money risk is a **GPU or forgotten machine**, which is why auto-expiry is a core feature.
- **Remote means you need internet at the venue.** If the Wi-Fi dies, the demo dies. Keep a fallback: a screen recording of a clean run, a phone hotspot.
- **It is a single-VM tool.** No Kubernetes. No autoscaling. 20 containers means Docker Compose on one machine.
- **Providers are not interchangeable.** They share a *config contract*, not behaviour. On both, a stopped instance stops compute billing and keeps billing for the disk and the public IP. Both give the VM an identity (an instance role on AWS, a service account on GCP). The CLI prints the cost of a stop every time.
- **Don't first-run it on demo day.** Quotas, account verification and stock-outs are real. Rehearse at least two days ahead.
- **If the repo, data or credentials belong to an employer or client, check their policy** on running them on a personal cloud account before using this.



## What it does


| Capability                                                                     | Phase |
| ------------------------------------------------------------------------------ | ----- |
| Hand-build the demo environment once (the baseline Terraform must beat)        | 0     |
| Create/destroy a VM from a *profile* on AWS: Docker installed, repo cloned     | 1a    |
| Generate SSH config; `open` = port forwards + VS Code on the repo              | 1a    |
| Same on GCP                                                                    | 1b    |
| Tag everything with an expiry; a reaper deletes expired machines               | 2     |
| Cost report for a planned period, per provider                                 | 3     |
| GPU / local-LLM profile (**only after the reaper works**)                      | 4     |




## Requirements

- Terraform ≥ 1.x (pinned in `.terraform-version`)
- Node.js 22+ (pricing and reaper tooling)
- `make`, `ssh`, VS Code with the **Remote - SSH** extension
- An account per provider you use — ideally a **dedicated sandbox account/project** with a **budget alert** (e.g. $20) set up first
- Least-privilege credentials for Terraform (never your admin credentials)
- GPU profiles: a granted quota (AWS starts at zero on new accounts; GCP varies by region). Request it days ahead
- *(Optional)* A Tailscale account — only if "Reaching your demo" below says you need it



## Quickstart (target interface)

```bash
# 1. Configure a profile (real *.tfvars files are gitignored)
cp profiles/demo-no-llm.example.tfvars profiles/demo-no-llm.tfvars
$EDITOR profiles/demo-no-llm.tfvars        # repo URL, region, allowed_cidrs, ttl_hours, ...

# 2. See exactly what will be created — and what it costs per hour
make plan PROVIDER=aws PROFILE=demo-no-llm

# 3. Create it
make up PROVIDER=aws PROFILE=demo-no-llm

# 4. Connect: writes ~/.ssh/config.d/demo-machines, starts port forwards, opens VS Code on the repo
make open PROVIDER=aws

# 5. Check what's running, TTL left, cost so far
make status

# 6. Tear down
make down PROVIDER=aws
```

**Reaching frontend ports:** VS Code Remote-SSH forwards ports automatically; or `ssh -L 3000:localhost:3000 demo-aws`. Nothing is opened to the internet by default.

## Configuration

Everything variable lives in a profile file. The **same variable names work on every provider**; only the values that map to provider concepts (region, size) differ.


| Variable                             | Meaning                                                                           | Default                                                                            |
| ------------------------------------ | --------------------------------------------------------------------------------- | ---------------------------------------------------------------------------------- |
| `name`                               | Resource name prefix                                                              | —                                                                                  |
| `region`                             | Provider region/zone                                                              | provider default                                                                   |
| `size`                               | Named size: `small`, `medium`, `large`, `gpu-24`, `gpu-48` (curated per provider) | `medium`                                                                           |
| `disk_gb`                            | Root disk                                                                         | `100`                                                                              |
| `ttl_hours`                          | Time until the reaper may delete it                                               | `12`                                                                               |
| `allowed_cidrs`                      | Who may reach SSH                                                                 | required; `make` fills in your current public IP (/32) if unset. Never `0.0.0.0/0` |
| `ssh_public_key_path`                | Key installed on the VM                                                           | —                                                                                  |
| `repo_url` / `repo_ref`              | What to clone and which ref                                                       | —                                                                                  |
| `git_auth`                           | `agent` (SSH agent forwarding) or `pat`                                           | `agent`                                                                            |
| `compose_file` / `compose_autostart` | Compose entry point; start it at boot                                             | — / `false`                                                                        |
| `forward_ports`                      | Ports you intend to forward                                                       | `[]`                                                                               |
| `tailscale_enabled`                  | **Fallback only:** join a tailnet using an ephemeral tagged key                   | `false`                                                                            |
| `llm`                                | `{ enabled, runtime, models[] }` for GPU profiles                                 | disabled                                                                           |
| `tags`                               | Extra tags/labels                                                                 | `{}`                                                                               |




## Reaching your demo (easiest first)

1. **SSH + port forwarding (default).** `make open` forwards your demo's ports to `localhost`. SSH accepts only your IP (`allowed_cidrs`). Nothing is public.
2. **Refresh your allowed IP** when it changes (new venue, new Wi-Fi): `make allow-my-ip` updates the firewall rule — a one-variable `terraform apply`.
3. **Tailscale — only if you need it:** reaching private/internal resources from the VM, giving another device private access (tablet, second screen), or an IP that changes too often for step 2. Uses an ephemeral, tagged key. Off by default.
4. **A public URL (e.g. Cloudflare Tunnel)** — only if the audience must open the demo themselves. Put access control in front and keep it short-lived.

Don't jump to 3 or 4 because they're fun: each adds an account, a secret and a failure mode.

## Lifecycle: what each command really means


| Provider | Stopped VM billed?                    | `pause` does                         | Gotchas                                               |
| -------- | ------------------------------------- | ------------------------------------ | ----------------------------------------------------- |
| AWS      | Compute no; disk and public IPv4 yes  | Stop instance                        | GPU quota; IP changes on restart                      |
| GCP      | Compute no; disk and reserved IPs yes | Stop instance                        | Pricing is per-vCPU/RAM SKU, not per instance         |


Rule of thumb: **if you won't use it within the same day,** `down` **it.** Re-provisioning is cheaper than paying for an idle box or forgetting it.

## State (local, on purpose)

Terraform state lives on your machine in `state/<provider>-<profile>.tfstate` (gitignored). It's a deliberate choice: single user, and the easiest way to learn (`terraform state list`, `terraform state show`).

- **It's a secret.** Anything sensitive that passes through Terraform ends up in it. Never commit it or paste it into chats or issues; keep it mode 600 on an encrypted disk.
- **Back it up** somewhere encrypted after each `up`/`down`. If you lose it, Terraform forgets machines that are still running and billing. The tag-based reaper can still find and delete them, or you can `terraform import` them back.
- **One state file per provider+profile**, so profiles never overwrite each other.
- It lives on one computer. Using a second laptop means copying the state file.



## Cost report (Phase 3)

```bash
npm run prices:fetch                                   # refresh cached unit prices from provider APIs
npm run cost -- --plan pricing/usage-plans/q4.yaml     # writes reports/<date>-cost.md and .csv
```

- Input: a **usage plan** (period, sessions, hours, lifecycle, providers) — see the brief for the format.
- Output: per-provider totals and breakdown, a **"forgot to destroy for 72h" line**, price-data age, and warnings for stale or manually overridden prices.
- **Accuracy target: ±15%** on compute + disk + IP. Egress, VAT, FX and credits are not modelled unless the plan says so.
- Prices come from provider APIs, **not scraped websites**. Gaps are filled in `pricing/overrides.yaml` with a date and source URL, and shown in the report.
- After real sessions, compare against the actual bill (`reports/accuracy.md`). Don't trust the estimate until you've done this at least once per provider.



## Security model

- **No secrets in git.** A secret scanner runs in CI; real `*.tfvars` are gitignored.
- **Terraform state is secret and local** (`state/`, gitignored, mode 600, encrypted disk, encrypted backup). `sensitive = true` hides terminal output only — it does not keep values out of state.
- **User-data is not private.** Never put tokens in it.
- **Git access:** prefer SSH agent forwarding (nothing stored on the VM). Fallback is a read-only, short-expiry PAT pushed over SSH.
- **Cloud access from the VM:** use an instance role on AWS, or an attached service account on GCP.
- **Private networks (only if needed):** Tailscale with ephemeral, tagged, pre-authorized keys and a tight ACL.
- **Everything on the VM can see everything the VM can see**, including every container in your demo stack. Grant the minimum, for the minimum time, then revoke.



## Cost safety

- Every resource is tagged `managed-by=demo-machines`, `owner`, `expires_at`.
- A **reaper** running outside the VM deletes expired resources on AWS and GCP. Powering the VM off stops compute billing and leaves the instance, disk and public IP in the account.
- Set budget alerts on every account. Treat them as the second line of defence, not the first.
- Default TTL is 12 hours. Extending it is an explicit action.



## Troubleshooting (grows with real failures)


| Symptom                                                | Likely cause                                                                                                                  |
| ------------------------------------------------------ | ----------------------------------------------------------------------------------------------------------------------------- |
| `VcpuLimitExceeded` / quota error on AWS GPU           | GPU quota is zero on new accounts; request an increase days ahead                                                             |
| GCP quota or zone capacity error                       | CPU or GPU quota, or the zone is out of stock; try another zone in the region, or request quota                               |
| VS Code can't connect                                  | `allowed_cidrs` doesn't include your current IP; or the IP changed after a restart                                            |
| Repo clone fails with agent auth                       | Agent not forwarded: check `ForwardAgent yes` for the host and `ssh-add -l` locally                                           |
| Estimate far from the bill                             | Missing disk/IP lines, stale prices, or the billing-granularity model is wrong — log it in `reports/accuracy.md`              |
| Terraform shows nothing but a machine is still running | State file lost, or wrong `PROVIDER`/`PROFILE` pair. Find it by tag (reaper dry-run), then delete it or `terraform import` it |
| Demo dies mid-showcase                                 | Venue internet. Use the fallback: screen recording, phone hotspot                                                             |




## Project docs

- [`_docs/00--project-brief.md`](_docs/00--project-brief.md) — goals, non-goals, risks, decisions, phases
- [`_docs/01--implementation-plan.md`](_docs/01--implementation-plan.md) — gated build order
- [`AGENTS.md`](AGENTS.md) — rules for AI coding agents working in this repo



## License

MIT.