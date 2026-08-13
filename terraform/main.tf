terraform {
    required_providers {
        aws = { source = "hashicorp/aws", version ="~> 5.60"}
        archive = {source = "hashicorp/archive", version = "~> 2.4" }
    }
}


provider "aws" {    
    region = "eu-central-1"
}


# --- zip handler.py at apply time ---
data "archive_file" "lambda_zip" {
    type    = "zip"
    source_file = "${path.module}/handler.py"
    output_path = "${path.module}/lambda.zip"
} 


# --- the role the Lambda assumes ---
resource "aws_iam_role" "lambda" {
    name = "trip-briefing-lambda-role"
    assume_role_policy = jsonencode({
        Version = "2012-10-17"
        Statement = [{
            Effect = "Allow"
            Principal = { Service = "lambda.amazonaws.com" }
            Action = "sts:AssumeRole"
        }]
    })
}


# --- permissions: call Bedrock + write logs ---
resource "aws_iam_role_policy" "lambda" {
  name = "trip-briefing-lambda-policy"
  role = aws_iam_role.lambda.id
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = ["bedrock:InvokeModel"]
        # profile + underlying regional models it routes to
        Resource = [
          "arn:aws:bedrock:*::foundation-model/anthropic.claude-*",
          "arn:aws:bedrock:*:*:inference-profile/eu.anthropic.claude-*"
        ]
      },
      {
        Effect   = "Allow"
        Action   = ["logs:CreateLogStream", "logs:PutLogEvents"]
        Resource = "${aws_cloudwatch_log_group.lambda.arn}:*"
      }
    ]
  })
}

resource "aws_cloudwatch_log_group" "lambda" {
  name              = "/aws/lambda/trip-briefing"
  retention_in_days = 7
}



resource "aws_lambda_function" "briefing" {
  function_name    = "trip-briefing"
  role             = aws_iam_role.lambda.arn
  handler          = "handler.lambda_handler"
  runtime          = "python3.12"
  filename         = data.archive_file.lambda_zip.output_path
  source_code_hash = data.archive_file.lambda_zip.output_base64sha256
  timeout          = 30 # the two-call agent loop needs more than the 3s default
  depends_on       = [aws_cloudwatch_log_group.lambda]
}


resource "aws_apigatewayv2_api" "http" {
    name    = "trip-briefing-api"
    protocol_type = "HTTP"
}


resource "aws_apigatewayv2_integration" "lambda" {
  api_id                 = aws_apigatewayv2_api.http.id
  integration_type       = "AWS_PROXY"
  integration_uri        = aws_lambda_function.briefing.invoke_arn
  payload_format_version = "2.0"
}


resource "aws_apigatewayv2_route" "briefing" {
  api_id    = aws_apigatewayv2_api.http.id
  route_key = "POST /briefing"
  target    = "integrations/${aws_apigatewayv2_integration.lambda.id}"
}


resource "aws_apigatewayv2_stage" "default" {
  api_id      = aws_apigatewayv2_api.http.id
  name        = "$default"
  auto_deploy = true
}


resource "aws_lambda_permission" "apigw" {
  statement_id  = "AllowAPIGatewayInvoke"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.briefing.function_name
  principal     = "apigateway.amazonaws.com"
  source_arn    = "${aws_apigatewayv2_api.http.execution_arn}/*/*"
}


output "api_url" {
  value = "${aws_apigatewayv2_stage.default.invoke_url}/briefing"
}