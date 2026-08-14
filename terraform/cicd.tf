data "aws_caller_identity" "current" {}

# Tells AWS to trust GitHub's OIDC token issuer
resource "aws_iam_openid_connect_provider" "github" {
  url             = "https://token.actions.githubusercontent.com"
  client_id_list  = ["sts.amazonaws.com"]
  thumbprint_list = ["6938fd4d98bab03faadb97b34396831e3780aea1"]
}

# The role the pipeline assumes
resource "aws_iam_role" "cicd" {
  name = "trip-briefing-cicd-plan"
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Principal = { Federated = aws_iam_openid_connect_provider.github.arn }
      Action    = "sts:AssumeRoleWithWebIdentity"
      Condition = {
        StringEquals = {
          "token.actions.githubusercontent.com:aud" = "sts.amazonaws.com"
        }
        # THE repo-scoped condition — only this repo's workflows can assume the role
        StringLike = {
          "token.actions.githubusercontent.com:sub" = "repo:abdul-raouf/weather-agent-with-terraform:*"
        }
      }
    }]
  })
}

# Plan needs: read everything, plus state bucket + lock table
resource "aws_iam_role_policy" "cicd" {
  name = "trip-briefing-cicd-plan-policy"
  role = aws_iam_role.cicd.id
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid      = "ReadForDriftDetection"
        Effect   = "Allow"
        Action   = ["lambda:Get*", "lambda:List*", "apigateway:GET",
                    "iam:Get*", "iam:List*", "logs:Describe*", "bedrock:Get*", "bedrock:List*"]
        Resource = "*"
      },
      {
        Sid      = "StateBucket"
        Effect   = "Allow"
        Action   = ["s3:GetObject", "s3:PutObject", "s3:ListBucket"]
        Resource = [
          "arn:aws:s3:::trip-briefing-tfstate-arauf-2026",
          "arn:aws:s3:::trip-briefing-tfstate-arauf-2026/*"
        ]
      },
      {
        Sid      = "StateLock"
        Effect   = "Allow"
        Action   = ["dynamodb:GetItem", "dynamodb:PutItem", "dynamodb:DeleteItem"]
        Resource = "arn:aws:dynamodb:eu-central-1:${data.aws_caller_identity.current.account_id}:table/trip-briefing-tflock"
      }
    ]
  })
}

output "cicd_role_arn" {
  value = aws_iam_role.cicd.arn
}