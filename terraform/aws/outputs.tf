output "public_ip" {
  description = "Auto-assigned public IPv4. Released when the instance is terminated. Not an Elastic IP."
  value       = aws_instance.this.public_ip
}

output "ssh_user" {
  description = "Ubuntu cloud image login."
  value       = "ubuntu"
}

output "instance_id" {
  description = "EC2 instance id."
  value       = aws_instance.this.id
}

output "expires_at" {
  description = "UTC RFC3339 expiry from the Makefile."
  value       = var.expires_at
}

output "ssh_public_key_path" {
  description = "Public key path from the profile. The SSH config strips the .pub suffix."
  value       = var.ssh_public_key_path
}

output "forward_ports" {
  description = "Ports make open forwards to 127.0.0.1."
  value       = var.forward_ports
}

output "git_auth" {
  description = "Git authentication mode. agent turns on ForwardAgent."
  value       = var.git_auth
}

output "repo_url" {
  description = "Clone URL. Empty means make open has no repo directory."
  value       = var.repo_url
}

output "repo_ref" {
  value = var.repo_ref
}

output "startup_command" {
  value = var.startup_command
}

output "autostart" {
  value = var.autostart
}

output "ttl_hours" {
  value = var.ttl_hours
}

output "name" {
  value = var.name
}

output "tailscale_enabled" {
  description = "Always false in this phase. Present so the profile contract is visible."
  value       = var.tailscale_enabled
}

output "llm_enabled" {
  description = "Always false until the reaper exists."
  value       = var.llm.enabled
}
