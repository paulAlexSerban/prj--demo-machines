locals {
  # Specs from the AWS T3 instance-type page. small is the cheap default.
  instance_types = {
    small  = "t3.small"   # 2 vCPU / 2 GiB
    medium = "t3.large"   # 2 vCPU / 8 GiB
    large  = "t3.2xlarge" # 8 vCPU / 32 GiB
  }

  instance_type = local.instance_types[var.size]

  # Any default subnet. This demo does not pin an availability zone.
  # An empty list means the region has no default subnet: stop, do not build a VPC.
  subnet_id = data.aws_subnets.default.ids[0]

  user_data = templatefile("${path.module}/../../bootstrap/cloud-init.yaml.tftpl", {
    bootstrap_b64 = base64encode(file("${path.module}/../../bootstrap/bootstrap.sh"))
  })
}

# SSH only. Demo ports stay closed; the laptop reaches them with ssh -L.
resource "aws_security_group" "ssh" {
  name        = "${var.name}-ssh"
  description = "SSH from allowed_cidrs only"
  vpc_id      = data.aws_vpc.default.id

  ingress {
    description = "ssh"
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = var.allowed_cidrs
  }

  # Outbound only, so apt, Docker Hub, DNS, and git can work.
  # Inbound stays limited to allowed_cidrs. A custom security group has no
  # default egress, so these rules are required.
  egress {
    description = "https"
    from_port   = 443
    to_port     = 443
    protocol    = "tcp"
    # trivy:ignore:AVD-AWS-0104
    cidr_blocks = ["0.0.0.0/0"]
  }

  egress {
    description = "http"
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    # trivy:ignore:AVD-AWS-0104
    cidr_blocks = ["0.0.0.0/0"]
  }

  egress {
    description = "dns"
    from_port   = 53
    to_port     = 53
    protocol    = "udp"
    # trivy:ignore:AVD-AWS-0104
    cidr_blocks = ["0.0.0.0/0"]
  }

  egress {
    description = "git ssh"
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    # trivy:ignore:AVD-AWS-0104
    cidr_blocks = ["0.0.0.0/0"]
  }
}

resource "aws_key_pair" "this" {
  key_name   = "${var.name}-ssh"
  public_key = file(var.ssh_public_key_path)
}

resource "aws_instance" "this" {
  ami                         = data.aws_ami.ubuntu.id
  instance_type               = local.instance_type
  subnet_id                   = local.subnet_id
  vpc_security_group_ids      = [aws_security_group.ssh.id]
  key_name                    = aws_key_pair.this.key_name
  associate_public_ip_address = true
  user_data                   = local.user_data

  # The security group and key pair are dependencies via their ids. No extra depends_on.

  root_block_device {
    volume_size           = var.disk_gb
    volume_type           = "gp3"
    encrypted             = true
    delete_on_termination = true
  }

  metadata_options {
    http_endpoint = "enabled"
    http_tokens   = "required"
  }

  tags = merge(var.tags, {
    Name = var.name
  })
}
