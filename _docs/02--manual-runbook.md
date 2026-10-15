# Phase 0 — by-hand baseline (AWS)

Fill this in while you do the session. The times are the baseline Terraform has to beat. Do not put tokens, private keys, or `.env` values in this file.

Region: **us-east-1** (N. Virginia). the console region selector has to say N. Virginia before you create anything.

One short session. Terminate the instance the same day. The budget alert should already be on.

`bootstrap/bootstrap.sh` is not written yet. It will be drafted from the commands you paste in the notes column.

## Session

| Field                                                  | Value                             |
| ------------------------------------------------------ | --------------------------------- |
| Date                                                   |                                   |
| Owner (tag value)                                      |                                   |
| `expires_at` (UTC ISO, same day)                       |                                   |
| Instance type (8 vCPU / 32 GiB; name from the console) |                                   |
| Root volume                                            | 100 GB gp3, delete on termination |
| Instance id                                            |                                   |
| Public IPv4                                            |                                   |
| Repo URL                                               |                                   |
| Repo ref                                               |                                   |
| Compose file                                           |                                   |
| Ports to forward                                       |                                   |
| Session start (UTC)                                    |                                   |
| Session end (UTC)                                      |                                   |
| Total minutes                                          |                                   |

## Rules for this run

- SSH port 22 from your current public IPv4 as a `/32` only. Never `0.0.0.0/0` or `::/0`.
- Do not open demo ports on the security group. Reach them with `ssh -L` from the laptop.
- Do not allocate an Elastic IP. Use the auto-assigned public IPv4. It is released when the instance is terminated.
- Tags on the instance: `managed-by=demo-machines`, `owner`, `expires_at`.
- Default VPC. If us-east-1 has no default VPC, stop and say so. Do not build a network by hand for this baseline.
- Ubuntu 24.04, SSH user `ubuntu`.
- No secrets in user-data. Clone with SSH agent forwarding, or skip the clone and write that down.

## Steps

Write the clock time in UTC. Minutes can be filled at the end. Paste the commands you actually ran into Notes.

| #   | Step                                                                                                                                                                                                                                                                                     | Start | End | Minutes | Notes (commands, ids, what failed) |
| --- | ---------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- | ----- | --- | ------- | ---------------------------------- |
| 1   | On the laptop, record your public IPv4. That address plus `/32` is the only SSH source.                                                                                                                                                                                                  |       |     |         |                                    |
| 2   | In the EC2 console, region N. Virginia, confirm a default VPC exists.                                                                                                                                                                                                                    |       |     |         |                                    |
| 3   | Create or select a key pair. Leave the private key on the laptop. Do not copy it into this repo.                                                                                                                                                                                         |       |     |         |                                    |
| 4   | Create a security group in the default VPC. Inbound: TCP 22 from your `/32` only. No other inbound rules.                                                                                                                                                                                |       |     |         |                                    |
| 5   | Launch Ubuntu 24.04. Size: 8 vCPU / 32 GiB (write the type name above). Root volume 100 GB gp3, delete on termination. Auto-assign public IPv4. Subnet: a default-VPC subnet. Security group from step 4. Key pair from step 3. Tags: `managed-by=demo-machines`, `owner`, `expires_at`. |       |     |         |                                    |
| 6   | Wait until the instance state is running and status checks pass. Record the instance id and public IPv4 above.                                                                                                                                                                           |       |     |         |                                    |
| 7   | SSH in: `ssh -i <key> -A ubuntu@<public-ip>`. `-A` turns on agent forwarding for the clone.                                                                                                                                                                                              |       |     |         |                                    |
| 8   | Install Docker Engine and the Compose plugin. Write the commands you ran.                                                                                                                                                                                                                |       |     |         |                                    |
| 9   | Confirm `docker version` and `docker compose version`. Log out and back in if the `docker` group is not active yet.                                                                                                                                                                      |       |     |         |                                    |
| 10  | Clone the repo at the ref above. If clone fails, stop and write the error. Do not embed a token in the URL.                                                                                                                                                                              |       |     |         |                                    |
| 11  | Optional: start the stack (`docker compose -f <compose file> up`). Skip this and say so if there is no compose file yet.                                                                                                                                                                 |       |     |         |                                    |
| 12  | From the laptop, forward each demo port: `ssh -i <key> -L <port>:127.0.0.1:<port> ubuntu@<public-ip>`. Open the app on `http://127.0.0.1:<port>`.                                                                                                                                        |       |     |         |                                    |
| 13  | Open VS Code Remote-SSH on `ubuntu@<public-ip>` and the repo directory.                                                                                                                                                                                                                  |       |     |         |                                    |
| 14  | Terminate the instance. Do not stop it and leave it.                                                                                                                                                                                                                                     |       |     |         |                                    |
| 15  | Confirm the instance is gone, the root EBS volume is gone, and there is no Elastic IP and no leftover public IPv4 for this run. Security group and key pair may stay; note what you deleted.                                                                                             |       |     |         |                                    |

## After the session

Hand this file back filled in, including the install and clone commands in the notes column. That is the input for `bootstrap/bootstrap.sh`.
