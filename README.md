# CloudOrder: Deployable Event-Driven Order Platform

CloudOrder is a portfolio project that demonstrates a production-style AWS serverless architecture. Its dashboard simulates API validation, queueing, asynchronous processing, and database storage in the browser—so it can be published free of charge without an AWS account.

## What you can show

- A polished operations dashboard, locally or at a public HTTPS URL after free deployment
- API Gateway + Lambda API with request validation
- SQS queue and DLQ for durable asynchronous processing
- A deployable AWS implementation with idempotent DynamoDB writes and `GET /orders/{order_id}` status API
- EventBridge audit events, CloudWatch DLQ alarm, scoped IAM, Terraform, tests, and CI

## Architecture

```text
CloudFront + S3 dashboard --> API Gateway --> ingest Lambda --> SQS queue --> processor Lambda --> DynamoDB
                                              |                  |
                                              +--> EventBridge    +--> DLQ
```

The visual dashboard mirrors this lifecycle entirely in the browser. The Terraform implementation remains included as a deployable AWS reference when an account becomes available.

## Publish free with GitHub Pages — recommended

GitHub Pages has no credit-card requirement. Create a free GitHub account if you do not have one, then:

1. Create a new **public** repository named `cloudorder` on GitHub.
2. Upload this project’s files to that repository and push them to the `main` branch.
3. In the repository, open **Settings → Pages** and set the source to **GitHub Actions**.
4. Open the **Actions** tab and wait for **Publish dashboard to GitHub Pages** to finish.

Your live portfolio URL will be:

```text
https://YOUR-GITHUB-USERNAME.github.io/cloudorder/
```

The included workflow publishes only the safe browser demo—there are no AWS credentials, charges, or backend secrets involved.

## Deploy a real serverless version for free with Cloudflare Workers

This option gives the project an actual API and persistent serverless storage, without AWS. Cloudflare states that its Workers Free plan needs no credit card and includes 100,000 requests per day. [Cloudflare Workers pricing](https://developers.cloudflare.com/workers/platform/pricing/) and [free-plan limits](https://developers.cloudflare.com/workers/platform/limits/) explain the current allowances.

1. Publish the project to GitHub first.
2. In Cloudflare, use **Workers & Pages → Create application → Import an existing Git repository** and select the GitHub repository.
3. Set the project root directory to `cloudflare` and use `npx wrangler deploy` as the deploy command if Cloudflare asks for one.
4. After the first deployment, create a Workers KV namespace named `cloudorder-orders` in the Cloudflare dashboard.
5. Open the Worker → **Settings → Bindings → Add → KV Namespace**. Set the variable name to `ORDERS`, choose `cloudorder-orders`, and select **Deploy**.

Cloudflare gives you a `https://cloudorder.<your-subdomain>.workers.dev` URL. Open it and submit an order: the browser will call the deployed Worker API, which persists the order in Cloudflare KV and returns its real processed status.

## Run locally (visual demo)

Open [Open CloudOrder Demo.cmd](Open%20CloudOrder%20Demo.cmd), or open `demo/index.html` in a browser. Local mode simulates the AWS workflow and needs no account.

## Optional: deploy the real AWS implementation later

If you later gain access to an AWS account, the `infra/` folder deploys a private S3 dashboard behind CloudFront, API Gateway, three Lambda functions, SQS/DLQ, DynamoDB, EventBridge, and a CloudWatch alarm. CloudFront provisioning normally takes 10–15 minutes.

1. Install [Terraform](https://developer.hashicorp.com/terraform/install).
2. Configure AWS credentials with permissions to create the listed resources.
3. In `infra`, copy `terraform.tfvars.example` to `terraform.tfvars`; change the AWS region if desired.
4. Run:

```bash
cd infra
terraform init
terraform validate
terraform apply
```

At the prompt, type `yes`. Terraform outputs a `dashboard_url`; open it in a browser and submit an order. This version calls the live API and reads its live processing status.

## Test the API directly

```bash
curl -X POST "<api_url>/orders" \
  -H "Content-Type: application/json" \
  -d '{"customer_id":"cust-101","items":[{"sku":"keyboard-01","quantity":1,"unit_price":69.99}]}'
```

The response contains an `order_id`. Request `GET <api_url>/orders/<order_id>` until it returns `200` with `status: PROCESSED`.

## Local tests

```bash
python -m pip install -r requirements-dev.txt
python -m pytest -q
```

## Cost and cleanup

AWS may charge small amounts for CloudFront, requests, and DynamoDB point-in-time recovery. Review the Terraform plan before deploying. When finished:

```bash
cd infra
terraform destroy
```

## Resume bullet

> Built CloudOrder, an event-driven AWS order-processing platform using API Gateway, Lambda, SQS/DLQ, DynamoDB, EventBridge, and Terraform; created a live GitHub Pages dashboard to demonstrate asynchronous order processing and system design.

See [docs/interview-notes.md](docs/interview-notes.md) for an interview-ready explanation.
