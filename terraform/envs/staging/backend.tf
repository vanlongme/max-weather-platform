terraform {
  backend "s3" {
    # bucket         = "max-weather-tfstate-<account-id>"
    # key            = "staging/terraform.tfstate"
    # region         = "ap-southeast-1"
    # dynamodb_table = "max-weather-tflock"
    # encrypt        = true
    # Uncomment and fill after bootstrap module is applied.
    # Run: cd terraform/envs/staging && terraform init -reconfigure
  }
}
