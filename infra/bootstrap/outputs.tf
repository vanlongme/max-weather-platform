output "tfstate_bucket_name" {
  description = "Name of the S3 bucket used for Terraform state storage."
  value       = aws_s3_bucket.tfstate.id
}

output "tfstate_bucket_arn" {
  description = "ARN of the S3 bucket used for Terraform state storage."
  value       = aws_s3_bucket.tfstate.arn
}

output "tflock_table_name" {
  description = "Name of the DynamoDB table used for Terraform state locking."
  value       = aws_dynamodb_table.tflock.id
}

output "tflock_table_arn" {
  description = "ARN of the DynamoDB table used for Terraform state locking."
  value       = aws_dynamodb_table.tflock.arn
}

output "tfstate_access_policy_json" {
  description = "IAM policy JSON document granting access to S3 state and DynamoDB lock. Attach to Jenkins/operator role."
  value       = data.aws_iam_policy_document.tfstate_access.json
  sensitive   = true
}
