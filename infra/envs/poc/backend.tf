terraform {
  backend "s3" {
    bucket         = "max-weather-tfstate-339712707744"
    key            = "envs/poc/terraform.tfstate"
    region         = "us-east-1"
    dynamodb_table = "max-weather-tflock"
    encrypt        = true
  }
}
