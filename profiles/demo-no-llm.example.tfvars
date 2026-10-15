# Copy to profiles/demo-no-llm.tfvars (gitignored) and set owner plus the public key path.
# size: small (default, t3.small) | medium (t3.large) | large (t3.2xlarge, 8 vCPU / 32 GiB).
# gpu-24 and gpu-48 are rejected until the reaper exists.
# For size = "large", set disk_gb = 100.

name      = "demo-no-llm"
region    = "us-east-1"
size      = "small"
disk_gb   = 30
ttl_hours = 12
owner     = "your-name"
# Relative to the repo root. ../.ssh/... from the profiles/ directory also works.
ssh_public_key_path = ".ssh/id_ed25519_demo-machines.pub"
repo_url            = ""
repo_ref            = "main"
git_auth            = "agent"
# startup_command = "make up"
startup_command = ""
autostart       = false
# forward_ports     = [8000, 8001, 8501, 8888, 3000]
forward_ports     = []
# Copied to ~/demo/.env over SSH (make open / make bootstrap). Not user-data.
# Values must be quoted strings. Real tokens belong in the gitignored tfvars copy.
env = {
  # DEMO_NAME = "set-me"
}
tailscale_enabled = false

llm = {
  enabled = false
  runtime = ""
  models  = []
}

tags = {}
