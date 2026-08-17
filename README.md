# ACI Capstone 1

AWS infrastructure for a serverless document-handling backend, provisioned entirely with Terraform.

## Architecture

![Serverless license onboarding platform: CloudFront serves the Next.js SPA over HTTPS from a private S3 bucket via OAC; the browser signs in with Cognito, gets a presigned URL from the app API, and uploads an applicant zip to the document bucket, where EventBridge starts a Step Functions execution running four Lambdas against Rekognition, Textract, DynamoDB and SQS](docs/Architecture.png?v=3)

Source: [`docs/aci-capstone1-serverless-backend.drawio`](docs/aci-capstone1-serverless-backend.drawio) — edit there and re-export, never edit the PNG. Conventions and layout rules for this diagram are documented in [`docs/draw_io.md`](docs/draw_io.md).

The 16 numbered badges on the canvas match the numbered legend on the right: 1–4 the browser plane (load the app, sign in, request an upload URL, upload), 5–12 the document pipeline, 13–14 submit and validate, 15 the status poll, 16 failure notifications. Solid arrows are the happy path, dashed ones are failure or return paths.

Greyed elements are **not** on the live request path, for two different reasons:

- **Auxiliary band** — the monolithic `DocumentLambda` is commented out in Terraform, superseded by the Step Functions pipeline; its role, policies and log group still deploy.
- **Custom domain band** — Route 53 + ACM are *not written at all*. Everything else in the diagram is deployed and proven end to end; the site simply answers on the distribution's default `*.cloudfront.net` name. That band documents what closing the gap would take.

## Stack

All resource names are stamped with `-${project_environment}` (e.g. `-dev`, `-prod`) at the env layer — see **Env-suffix naming** below. Each service below is provisioned by its own Terraform sub-module; see that module's `README.md` for resource-level detail, inputs/outputs, and gotchas.

- **S3** (`infrastructure/modules/s3/`) — document storage bucket: TLS-only, encrypted with its own KMS customer managed key (SSE-KMS + bucket keys), with lifecycle rules expiring `zipped/`/`unzipped/` objects after 30 days. It holds PII — selfies and driver's licenses — so nothing is retained indefinitely.
- **DynamoDB** (`infrastructure/modules/dynamodb/`) — `CustomerMetadataTable`, keyed by `APP_UUID`.
- **Lambda** (`infrastructure/modules/lambda/`) — six deployed functions. Four (unzip → write-to-dynamo → compare-faces → compare-details) are the live pipeline, sequenced by Step Functions; they run face-match (Rekognition) and ID-field extraction (Textract) checks, record results in DynamoDB, and notify via SNS. A validation/submit-license pair backs the API Gateway + SQS validation hop. A seventh, the monolithic document Lambda that did all of the above in one handler, is **commented out** — superseded by the pipeline, source retained.
- **Step Functions** (`infrastructure/modules/stepFunction/`) — `DocumentStateMachine`, plus the S3 → EventBridge → Step Functions chain that starts an execution on every `zipped/` upload. X-Ray tracing is enabled end to end; `WriteToDynamoLambdaFunction` is additionally instrumented with AWS Lambda Powertools, so its S3 and DynamoDB calls show as individual subsegments (CloudWatch → Application Signals → Traces).
- **SNS** (`infrastructure/modules/sns/`) — `ApplicationNotifications` topic with email subscription.
- **API Gateway** (`infrastructure/modules/apiGateway/`) — `ValidateLicenseApi`, one HTTP API serving two audiences: internal `POST /license` (IAM-signed, not browser-facing) and the browser-facing `POST /api/upload-url` + `GET /api/status/{uuid}` (Cognito JWT-authorized).
- **SQS** (`infrastructure/modules/sqs/`) — `LicenseQueue` + dead-letter queue, carrying the state machine's final message to the submit-license Lambda.
- **Cognito** (`infrastructure/modules/cognito/`) — user pool + public SPA app client backing the frontend's login; the JWT authorizer on the `/api/*` routes above trusts this pool.
- **S3 site bucket** (`infrastructure/modules/s3Site/`) — private bucket holding the built Next.js frontend; not readable directly, it's the CloudFront origin below.
- **CloudFront** (`infrastructure/modules/cloudfront/`) — HTTPS distribution in front of the site bucket via Origin Access Control (OAC), plus an edge function that resolves `/login` and `/login/` to the static export's `login/index.html`. This is the URL a new user opens to see the deployed frontend — see the `cloudfront_url` Terraform output.

All resources deploy to `us-east-1`.

## Request flow

```
upload <app_uuid>.zip to s3://<bucket>/zipped/
  └─ EventBridge rule (modules/stepFunction/)
      └─ DocumentStateMachine
          1. unzip              → extracts to unzipped/, returns app_uuid
          2. write-to-dynamo    → parses details CSV → DynamoDB row
          3. parallel:
             a. compare-faces   → Rekognition selfie vs license  → LICENSE_SELFIE_MATCH
             b. compare-details → Textract license vs CSV        → LICENSE_DETAILS_MATCH
          4. sendMessage → LicenseQueue
              └─ submit-license Lambda → POST /license (API Gateway → validation Lambda)
                  └─ LICENSE_VALIDATION → DynamoDB;  failures → SNS
```

Steps 3a/3b raise on a mismatch, which aborts the execution before step 4 — a failed application never reaches the queue. Per-step detail lives in `modules/stepFunction/README.md` and `modules/lambda/README.md`.

## Observability

AWS X-Ray tracing is enabled on `DocumentStateMachine` and on `WriteToDynamoLambdaFunction`. View traces in the console under **CloudWatch → Application Signals (APM) → Traces**.

**State machine — every state in one trace.** Enabling `tracing_configuration` on the state machine gives a timed segment per state, including both `PerformParallelChecks` branches and the final SQS send:

![X-Ray trace of DocumentStateMachine showing timed segments for each state, including both parallel branches and the SQS send](docs/X-Ray_tracing_stepfunctions.png)

**Lambda — inside a single function.** `WriteToDynamoLambdaFunction` additionally has `tracing_config { mode = "Active" }` and the AWS Lambda Powertools layer, so its handler is broken down further: a `## lambda_handler` subsegment with the individual S3 and DynamoDB calls nested beneath it:

![X-Ray trace of WriteToDynamoLambdaFunction showing the lambda_handler subsegment with nested S3 and DynamoDB calls](docs/X-Ray_tracing_writedynamolambda.png)

The other three pipeline Lambdas are untraced and appear as flat call targets — tracing adds roughly 700ms of cold-start time for the layer, so it's applied selectively.

> Both require `xray:*` permissions on their **own** IAM role. Without them, tracing still reports as enabled and executions still succeed, but no trace data is ever emitted and nothing logs an error. See `modules/stepFunction/README.md` and `modules/lambda/README.md`.

## Prerequisites

Everything below is required before a first `terraform apply` — Terraform won't tell you if one is missing, it'll just fail partway through.

- Terraform `>= 1.10.0`
- AWS CLI configured with credentials that can assume the deployment role
- Access to the remote-state bucket `aci-capstone1-remote-state` — it's a one-time bootstrap bucket outside this config; `terraform init` needs it to already exist
- [`bun`](https://bun.sh) installed and on `PATH` — the deploy step shells out to `bun run build` to compile the frontend before syncing it to S3
- `infrastructure/envs/dev/terraform.tfvars` created locally — it's gitignored (contains environment-specific and sensitive values) and is **not** generated for you; copy the variable names from `infrastructure/envs/dev/variables.tf` and fill in real values. `seed_users` (demo Cognito logins) is required and `sensitive`.

### First deploy

```bash
cd infrastructure/envs/dev
terraform init
terraform apply
```

One manual step after `apply` finishes: **confirm the SNS email subscription.** `terraform apply` triggers a confirmation email to `app_notification_email_endpoint` (set in `terraform.tfvars`); `ApplicationNotifications` won't deliver anything until you click the link. Nothing else needs manual intervention — one `apply` brings up all ten modules (including building and deploying the frontend), and one `terraform destroy` tears them back down, no console clicking required either direction. The deployed frontend's URL is the `cloudfront_url` output (`terraform output cloudfront_url`).

## Project Layout

```
.
├── infrastructure/
│   ├── modules/
│   │   ├── s3/                # Document bucket (SSE-KMS + lifecycle) + CMK + TLS-only policy
│   │   │   ├── s3.tf
│   │   │   ├── kms.tf          # customer managed key encrypting the bucket
│   │   │   ├── s3_policies.tf  # TLS-only bucket policy
│   │   │   ├── variables.tf
│   │   │   ├── outputs.tf
│   │   │   └── README.md
│   │   ├── dynamodb/          # CustomerMetadataTable
│   │   │   ├── dynamodb.tf
│   │   │   ├── variables.tf
│   │   │   ├── outputs.tf
│   │   │   └── README.md
│   │   ├── lambda/            # IAM (roles + inline + managed), 8 Lambda functions, log groups, SQS trigger
│   │   │   ├── lambda_policies.tf              # roles, inline + managed policies, attachments, log groups
│   │   │   ├── document_lambda_function.tf     # monolithic document function — entirely commented out
│   │   │   ├── validate_lambda_function.tf     # validation function + archive_file
│   │   │   ├── submit_license_lambda_function.tf # submit-license function + archive_file + SQS event source mapping
│   │   │   ├── unzip_lambda_function.tf        # unzip function + archive_file (invoked by the state machine)
│   │   │   ├── write_to_dynamo_lambda_function.tf # write-to-dynamo function + archive_file (invoked by the state machine)
│   │   │   ├── compare_faces_lambda_function.tf   # compare-faces function + archive_file (invoked by the state machine)
│   │   │   ├── compare_details_lambda_function.tf # compare-details function + archive_file (invoked by the state machine)
│   │   │   ├── app_api_lambda_function.tf      # browser-facing app API function + archive_file (no trigger yet — see modules/lambda/README.md)
│   │   │   ├── src/                            # Python handlers (s3_upload.py, validate_lambda.py, submit_license.py, unzip_lambda.py, write_to_dynamo_lambda.py, compare_faces_lambda.py, compare_details_lambda.py, app_api_lambda.py)
│   │   │   ├── build/                      # archive_file zip output (gitignored)
│   │   │   ├── variables.tf
│   │   │   ├── outputs.tf
│   │   │   └── README.md
│   │   ├── sns/               # ApplicationNotifications topic + email sub
│   │   │   ├── sns.tf
│   │   │   ├── variables.tf
│   │   │   ├── outputs.tf
│   │   │   └── README.md
│   │   ├── apiGateway/        # ValidateLicenseApi HTTP API: POST /license (IAM) -> Validate; /api/* (Cognito JWT) -> AppApi
│   │   │   ├── apigw.tf
│   │   │   ├── variables.tf
│   │   │   ├── outputs.tf
│   │   │   └── README.md
│   │   ├── sqs/               # LicenseQueue + LicenseDeadLetterQueue (DLQ)
│   │   │   ├── sqs.tf
│   │   │   ├── variables.tf
│   │   │   ├── outputs.tf      # exposes queue arn, DLQ arn, queue name, queue url
│   │   │   └── README.md
│   │   ├── stepFunction/      # DocumentStateMachine + S3 -> EventBridge -> Step Functions trigger
│   │   │   ├── DocumentStateMachine.tf  # state machine, its IAM role/policy, bucket notification, EventBridge rule/target/role
│   │   │   ├── variables.tf
│   │   │   ├── outputs.tf
│   │   │   └── README.md
│   │   ├── cognito/           # User pool + public SPA app client + seed users (frontend auth)
│   │   │   ├── congnito.tf     # note: filename is misspelled, left alone to avoid a state move
│   │   │   ├── variables.tf
│   │   │   ├── outputs.tf
│   │   │   └── README.md
│   │   ├── s3Site/             # Private bucket holding the built frontend — CloudFront's OAC origin, not a website host
│   │   │   ├── s3.tf            # bucket + public access block (all four flags true)
│   │   │   ├── variables.tf
│   │   │   ├── outputs.tf
│   │   │   └── README.md
│   │   └── cloudfront/         # OAC distribution + edge rewrite function + site bucket policy, fronting s3Site over HTTPS
│   │       ├── cloudfront.tf
│   │       ├── rewrite_uri.js   # edge function: resolves /login and /login/ to login/index.html
│   │       ├── variables.tf
│   │       ├── outputs.tf
│   │       └── README.md
│   └── envs/
│       └── dev/
│           ├── backend.tf       # state at envs/dev/terraform.tfstate
│           ├── main.tf          # composes all 10 sub-modules
│           ├── variables.tf     # pass-through declarations
│           ├── outputs.tf       # forwards each sub-module's outputs
│           └── terraform.tfvars # gitignored
└── frontend/                # Next.js frontend — see frontend/CLAUDE.md and frontend_tutorial.md
```

The structure is **per-resource sub-modules composed by the env**. Only `dev` exists today; a `prod` env can be added later by copying `dev/`, swapping the backend `key`, and setting `project_environment = "prod"` in the new `terraform.tfvars` — the base names stay identical and the env-suffix pattern (see below) makes every resource land as `*-prod` automatically.

## Env-suffix naming

Every resource name is stamped with `-${var.project_environment}` (e.g. `-dev`, `-prod`) at the env layer, so multiple envs can coexist in one AWS account without colliding on globally-unique names. See `CLAUDE.md`'s "Env-suffix naming pattern" for the mechanism and exceptions.

## Common Commands

Run from inside an env directory (e.g., `cd infrastructure/envs/dev`):

```bash
terraform init                # download providers/modules, configure backend
terraform plan                # preview changes
terraform apply               # apply changes
terraform destroy             # tear everything down
terraform validate            # syntax check
terraform fmt -recursive      # format
```

## State Management

Remote state lives in S3 (`aci-capstone1-remote-state`, `us-east-1`) with native S3 locking (`use_lockfile = true`). State key:

- `envs/dev/terraform.tfstate`

State is encrypted at rest: the backend sets `encrypt = true`, and the bucket itself has SSE-S3 (`AES256`) default encryption.

Configured in `envs/dev/backend.tf`. Do **not** commit local `.tfstate` files — `.gitignore` already excludes them. Any change to the backend block needs `terraform init -reconfigure` before `plan`/`apply` will run.

## Variables

`terraform.tfvars` is **gitignored** because it contains environment-specific values. Variables flow in two layers (sub-module ⇄ env). To add a new input to an existing sub-module:

1. Declare it in `infrastructure/modules/<sub>/variables.tf` with `type` + validation
2. Use it in the sub-module's `.tf` resources
3. Add a pass-through declaration in `envs/dev/variables.tf`
4. Set the value in `envs/dev/terraform.tfvars`
5. Forward it inside the `module "<sub>" { ... }` block in `envs/dev/main.tf`

**Shortcut:** if a value is identical across envs, hardcode it directly in the env's `module` call (skip steps 3–4) or give it a `default` in the sub-module's `variables.tf`.

To add a brand-new sub-module: create `infrastructure/modules/<name>/{main.tf,variables.tf,outputs.tf,README.md}`, then add `module "<name>" { source = "../../modules/<name>" ... }` to `envs/dev/main.tf`.

## Cross-module values

Sub-modules are isolated scopes — shared values (bucket ARN, table ARN, topic ARN, etc.) flow through the env's `main.tf`, which reads each module's `outputs.tf` and passes values into the next module's inputs. See `modules/lambda/README.md`'s "Cross-module dependencies" for the full wiring diagram (it's the biggest consumer of cross-module values).

## Default Tags

Every resource inherits these tags via the provider's `default_tags` block:

| Tag          | Value                       |
|--------------|-----------------------------|
| `Project`    | `var.project_name`          |
| `Environment`| `var.project_environment`   |
| `Owner`      | `var.project_owner`         |
| `ManagedBy`  | `Terraform`                 |

Pinned module versions and Terraform-specific notes/gotchas live in `CLAUDE.md` and each module's own `README.md`.

## License

Licensed under the **Apache License, Version 2.0** — see [`LICENSE`](LICENSE). Every first-party source file carries a matching `SPDX-License-Identifier: Apache-2.0` header.

One exception: the shadcn/ui components generated into `frontend/components/ui/` and `frontend/lib/utils.ts` are **MIT** (Copyright © 2023 shadcn) and stay under that license. See [`NOTICE`](NOTICE) for the details and for the Base UI attribution those components inherit.
