terraform {
  backend "s3" {
    bucket         = "trip-briefing-tfstate-arauf-2026" # must match the bucket above exactly
    key            = "trip-briefing/terraform.tfstate"
    region         = "eu-central-1"
    dynamodb_table = "trip-briefing-tflock"
    encrypt        = true
  }
}