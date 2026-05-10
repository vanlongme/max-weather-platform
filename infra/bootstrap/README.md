# Bootstrap: Terraform State Backend

Creates the S3 bucket and DynamoDB table required for Terraform remote state.

## Why a separate bootstrap?

This module uses a **local backend** to avoid the chicken-and-egg problem: you
cannot use S3 remote state before the S3 bucket exists.

## Usage

```bash
cd infra/bootstrap
cp terraform.tfvars.example terraform.tfvars
# Edit terraform.tfvars with your values
terraform init
terraform apply
```

After apply, note the outputs:

- `tfstate_bucket_name` — use in `backend "s3" { bucket = "..." }`
- `tflock_table_name` — use in `backend "s3" { dynamodb_table = "..." }`

## Outputs

| Name | Description |
|---|---|
| `tfstate_bucket_name` | S3 bucket name for Terraform state |
| `tfstate_bucket_arn` | S3 bucket ARN |
| `tflock_table_name` | DynamoDB table name for state locking |
| `tflock_table_arn` | DynamoDB table ARN |
| `tfstate_access_policy_json` | IAM policy JSON for Jenkins/operator role (sensitive) |

## Security

- Versioning enabled (90-day noncurrent expiry)
- AES256 server-side encryption
- All public access blocked (4 block settings = true)
- `prevent_destroy = true` on the S3 bucket

## Teardown

```bash
# Remove prevent_destroy from main.tf, then:
terraform destroy
```
