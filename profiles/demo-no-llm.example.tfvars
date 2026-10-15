# Copy to profiles/demo-no-llm.tfvars (gitignored) and set owner plus the public key path.
# size: small (default, t3.small) | medium (t3.large) | large (t3.2xlarge, 8 vCPU / 32 GiB).
# gpu-24 and gpu-48 are rejected until the reaper exists.
# For size = "large", set disk_gb = 100.

name                = "demo-no-llm"
region              = "us-east-1"
size                = "small"
disk_gb             = 30
ttl_hours           = 12
owner               = "your-name"
ssh_public_key_path = "/absolute/path/to/id_ed25519.pub"
repo_url            = ""
repo_ref            = "main"
git_auth            = "agent"
compose_file        = ""
compose_autostart   = false
forward_ports       = []
tailscale_enabled   = false

llm = {
  enabled = false
  runtime = ""
  models  = []
}

tags = {}
