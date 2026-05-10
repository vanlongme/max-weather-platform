terraform {
  backend "s3" {
    bucket         = "REPLACE_WITH_BOOTSTRAP_BUCKET_NAME"
    key            = "envs/poc/terraform.tfstate"
    region         = "us-east-1"
    dynamodb_table = "REPLACE_WITH_BOOTSTRAP_DYNAMODB_TABLE"
    encrypt        = true
  }
}
