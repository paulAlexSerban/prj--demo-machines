variable "name" {
  description = "Resource name prefix."
  type        = string

  validation {
    condition     = can(regex("^[a-z][a-z0-9-]{0,30}$", var.name))
    error_message = "name must start with a letter and contain only lowercase letters, digits, and hyphens."
  }
}

variable "region" {
  description = "AWS region. The example profile uses us-east-1."
  type        = string
  default     = "us-east-1"

  validation {
    condition     = length(var.region) > 0
    error_message = "region must not be empty."
  }
}

variable "size" {
  description = "Named size. small is t3.small, medium is t3.large, large is t3.2xlarge (8 vCPU / 32 GiB)."
  type        = string
  default     = "small"

  validation {
    condition     = contains(["small", "medium", "large"], var.size)
    error_message = "size must be small, medium, or large. gpu-24 and gpu-48 are rejected until the reaper exists."
  }
}

variable "disk_gb" {
  description = "Root gp3 volume size in GiB. The cheap default is 30. Use 100 with size large."
  type        = number
  default     = 30

  validation {
    condition     = var.disk_gb >= 8 && var.disk_gb <= 1024
    error_message = "disk_gb must be between 8 and 1024."
  }
}

variable "ttl_hours" {
  description = "Lifetime hint. The Makefile turns this into expires_at once and reuses that value."
  type        = number
  default     = 12

  validation {
    condition     = var.ttl_hours > 0
    error_message = "ttl_hours must be greater than 0."
  }
}

variable "expires_at" {
  description = "UTC RFC3339 expiry, passed by the Makefile. timestamp() is not called here: it changes on every plan and would rewrite the tag forever."
  type        = string

  validation {
    condition     = can(regex("^[0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9]{2}:[0-9]{2}:[0-9]{2}Z$", var.expires_at))
    error_message = "expires_at must look like 2026-10-14T18:00:00Z."
  }
}

variable "owner" {
  description = "Tag value for owner."
  type        = string

  validation {
    condition     = length(var.owner) > 0
    error_message = "owner must not be empty."
  }
}

variable "allowed_cidrs" {
  description = "CIDRs allowed to SSH. Make fills your current public IPv4 as a /32 when this is unset in the profile."
  type        = list(string)

  validation {
    condition = length(var.allowed_cidrs) > 0 && alltrue([
      for cidr in var.allowed_cidrs :
      cidr != "0.0.0.0/0" && cidr != "::/0" && can(cidrhost(cidr, 0))
    ])
    error_message = "allowed_cidrs must be one or more CIDRs and must not contain 0.0.0.0/0 or ::/0."
  }
}

variable "ssh_public_key_path" {
  description = "Public key installed on the VM. In a profile, a relative path is from the repo root (.ssh/id_ed25519.pub) or from the profile file (../.ssh/id_ed25519.pub). make turns it into an absolute path because Terraform looks next to terraform/aws."
  type        = string

  validation {
    condition     = fileexists(var.ssh_public_key_path)
    error_message = "ssh_public_key_path must be an existing public key file."
  }
}

variable "repo_url" {
  description = "Git URL to clone over SSH later. Empty skips the clone. Not used by cloud-init."
  type        = string
  default     = ""
}

variable "repo_ref" {
  description = "Git ref to check out when cloning over SSH."
  type        = string
  default     = "main"
}

variable "git_auth" {
  description = "How git authenticates. Only agent is accepted. A PAT must never be placed in tfvars or user-data."
  type        = string
  default     = "agent"

  validation {
    condition     = var.git_auth == "agent"
    error_message = "git_auth must be agent. Do not put a PAT in tfvars or user-data."
  }
}

variable "compose_file" {
  description = "Compose file path relative to the cloned repo. Used only when bootstrap.sh is run over SSH."
  type        = string
  default     = ""
}

variable "compose_autostart" {
  description = "When true, bootstrap.sh over SSH runs docker compose up -d. Cloud-init does not start the stack."
  type        = bool
  default     = false
}

variable "forward_ports" {
  description = "Ports make open forwards to 127.0.0.1. Nothing is opened on the security group."
  type        = list(number)
  default     = []

  validation {
    condition     = alltrue([for port in var.forward_ports : port > 0 && port < 65536])
    error_message = "forward_ports must be between 1 and 65535."
  }
}

variable "tailscale_enabled" {
  description = "Reserved. Tailscale is not wired into this phase."
  type        = bool
  default     = false

  validation {
    condition     = var.tailscale_enabled == false
    error_message = "tailscale_enabled must be false. Tailscale is not part of the default path."
  }
}

variable "llm" {
  description = "Reserved GPU profile. Disabled until the reaper exists."
  type = object({
    enabled = bool
    runtime = string
    models  = list(string)
  })
  default = {
    enabled = false
    runtime = ""
    models  = []
  }

  validation {
    condition     = var.llm.enabled == false
    error_message = "llm.enabled must be false. GPU profiles are rejected until the reaper exists."
  }
}

variable "tags" {
  description = "Extra tags merged onto the instance name tag. managed-by, owner, and expires_at come from provider default_tags."
  type        = map(string)
  default     = {}
}
