# Trip Briefing Agent — Serverless Agentic AI on AWS

A small agentic AI service deployed entirely on AWS, provisioned as Terraform
infrastructure-as-code. Given a destination, an LLM decides whether to call a
weather tool, then composes a short travel briefing. Built as a focused
exercise in cloud deployment, IaC, and production concerns — not a product.

## What it does

You POST a destination to an HTTPS endpoint. Behind it, a Lambda runs an
agent loop against Amazon Bedrock (Claude): the model decides — per request —
whether it needs a weather forecast, calls the `open-meteo` tool if so, and
writes a packing/planning briefing from real forecast data. If the tool fails,
the agent degrades gracefully and still responds.

## Architecture

```
mermaid
flowchart TD
    Client([Client - Postman / curl / browser])
    APIGW[API Gateway - HTTP API]
    Lambda[Lambda: trip-briefing - Python 3.12]
    Bedrock[Amazon Bedrock - Claude Haiku 4.5 / EU inference profile]
    Meteo[open-meteo - weather tool]
    Logs[(CloudWatch Logs - structured JSON)]

    Client -->|POST /briefing| APIGW
    APIGW --> Lambda
    Lambda <-->|Converse API tool-use loop| Bedrock
    Lambda <-->|tool call| Meteo
    Lambda --> Logs

    subgraph IaC["Provisioned by Terraform (IaC)"]
        TF[Terraform]
        S3[(S3 - remote state)]
        DDB[(DynamoDB - state lock)]
        TF --- S3
        TF --- DDB
    end

    IaC -.provisions.-> APIGW
    IaC -.provisions.-> Lambda
    IaC -.provisions.-> Logs
```

Runtime path: API Gateway (HTTP API) → Lambda (Python 3.12) → Bedrock, with
`open-meteo` as a callable tool and structured logs to CloudWatch. The entire
stack — including remote state — is defined in Terraform.

## Key design decisions

- **Amazon Bedrock over self-hosted models** — no GPU to run or pay for, and
  Bedrock's EU inference profiles keep data in-region for GDPR/residency.
  An on-prem Ollama build exists separately as a privacy-preserving reference.
- **EU inference profiles** — Claude is invoked via an `eu.` profile that
  routes across EU regions; the Lambda's IAM policy allows both the profile
  and the underlying regional model ARNs.
- **Genuinely agentic, not a pipeline** — the LLM controls the loop via
  Bedrock's tool-use (Converse API). Tool calls are conditional on the model's
  decision, not hard-coded. Verified in logs: irrelevant queries skip the tool.
- **Serverless (Lambda + API Gateway)** — scales to zero, near-zero cost for a
  learning workload.
- **Terraform with remote state** — state in S3, locking via DynamoDB, so the
  stack is reproducible and safe to tear down and rebuild identically.
- **Structured JSON logging** — every request logs the model's decisions,
  tool calls, and latency, queryable in CloudWatch.

## Tech stack

AWS Lambda · API Gateway (HTTP API) · Amazon Bedrock (Claude) · DynamoDB ·
CloudWatch · Terraform · Python 3.12

## Deploy

Prerequisites: an AWS account with Bedrock model access enabled for Claude,
the AWS CLI configured, and Terraform >= 1.9.

```
  terraform init
  terraform plan
  terraform validate
  terraform apply
```

`apply` outputs the API URL. Call it:

[fenced block:
  curl.exe -X POST "<api_url>" -H "Content-Type: application/json" -d "@payload.json" ]

Tear down with `terraform destroy`.

## Notes and trade-offs

- **Cost**: designed for the AWS free tier; Bedrock is pay-per-token and
  negligible at this volume. Tear down when not in use.
- **Observed performance**: ~[X]ms typical, ~[Y]ms when a tool call adds a
  second model turn. [Pull real numbers from your CloudWatch logs.]
- **Deploy-time IAM**: the deploying identity uses broad managed policies for
  convenience. In a real setup this would be a scoped custom policy or an
  assumed deployment role.
- **Not yet added**: CI/CD (GitHub Actions with OIDC federation) and a
  DynamoDB memory layer for cross-request personalization.

## License

MIT