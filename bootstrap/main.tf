terraform {
  required_providers {
    aws = { source = "hashicorp/aws", version = "~> 5.60" }
  }
}

provider "aws" {
  region = "eu-central-1"
}

resource "aws_s3_bucket" "state" {
  bucket = "trip-briefing-tfstate-arauf-2026" # globally unique — change if taken
}

resource "aws_s3_bucket_versioning" "state" {
  bucket = aws_s3_bucket.state.id
  versioning_configuration { status = "Enabled" } # lets you roll back a bad state
}

resource "aws_s3_bucket_server_side_encryption_configuration" "state" {
  bucket = aws_s3_bucket.state.id
  rule {
    apply_server_side_encryption_by_default { sse_algorithm = "aws:kms" }
  }
}

resource "aws_dynamodb_table" "lock" {
  name         = "trip-briefing-tflock"
  billing_mode = "PAY_PER_REQUEST" # no idle cost — bills per lock, effectively free here
  hash_key     = "LockID"
  attribute {
    name = "LockID"
    type = "S"
  }
}