# Jenkins Module

Provisions a Jenkins EC2 instance (t3.medium) with:
- Ubuntu 22.04 LTS base
- IAM instance profile (no static AWS keys)
- Docker, kubectl 1.30, helm 3, awscli v2
- Jenkins LTS (Debian package)
- Elastic IP for stable URL
- Security group: ingress restricted to `var.allowed_cidrs` only

## Usage

```hcl
module "jenkins" {
  source = "../../modules/jenkins"

  vpc_id                = module.networking.vpc_id
  public_subnet_id      = module.networking.public_subnet_ids[0]
  instance_profile_name = module.iam.jenkins_instance_profile_name
  key_name              = "my-key-pair"
  allowed_cidrs         = ["1.2.3.4/32"]

  tags = local.common_tags
}
```

## Inputs

| Name | Description | Type | Default |
|---|---|---|---|
| `name_prefix` | Resource name prefix. | `string` | `"max-weather"` |
| `vpc_id` | VPC ID. | `string` | — |
| `public_subnet_id` | Public subnet to deploy into. | `string` | — |
| `instance_profile_name` | IAM instance profile name. | `string` | — |
| `key_name` | EC2 key pair name. | `string` | — |
| `allowed_cidrs` | Allowed CIDRs for port 8080 + SSH. | `list(string)` | — |
| `instance_type` | EC2 instance type. | `string` | `"t3.medium"` |
| `root_volume_size` | Root EBS volume GB. | `number` | `30` |
| `tags` | Resource tags. | `map(string)` | `{}` |

## Outputs

| Name | Description |
|---|---|
| `instance_id` | Jenkins instance ID. |
| `instance_public_ip` | Public IP (unstable). |
| `instance_public_dns` | Public DNS. |
| `eip_address` | Stable Elastic IP. |
| `jenkins_url` | Jenkins UI URL. |

## Initial Admin Password

After ~5 minutes from launch, SSH in and run:
```bash
cat /home/ubuntu/initialAdminPassword
```
Or retrieve via `/var/lib/jenkins/secrets/initialAdminPassword`.
