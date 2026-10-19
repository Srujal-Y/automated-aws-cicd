# AWS and GitHub setup

This procedure creates billable AWS infrastructure. It is not required to run local tests. Use a dedicated sandbox with authorised administrator/bootstrap credentials. Do not use root account access keys. Set an AWS budget and review the Terraform plans before applying them.

## 1. Publish this folder as its own repository

Use this folder as the Git repository root so `.github/workflows` is recognised. For example, use `Srujal-Y/automated-aws-cicd`. The GitHub repository must match `github_repository` in Terraform. Existing Three Tier infrastructure is not reused.

## 2. Create remote state storage

Choose a globally unique bucket name and configure AWS CLI authentication (for example via your organisation's IAM Identity Center profile). All three stacks should use the same region.

```powershell
$env:AWS_PROFILE = "YOUR_AUTHORISED_PROFILE"
terraform -chdir=infra/state init
terraform -chdir=infra/state plan -var="bucket_name=YOUR_UNIQUE_STATE_BUCKET" -var="region=us-east-1"
terraform -chdir=infra/state apply -var="bucket_name=YOUR_UNIQUE_STATE_BUCKET" -var="region=us-east-1"
```

The state stack starts with local state to solve the bucket bootstrap dependency. Store its state securely; it is excluded from Git. For team use, add `backend "s3" {}` inside that stack's Terraform block after the bucket exists and run `terraform init -migrate-state` with bucket/key/region/encrypt/use_lockfile settings. Use a separate key such as `delivery-platform/bootstrap/state.tfstate`. The bucket has `prevent_destroy` and is intentionally outside application teardown.

## 3. Provision the platform

Copy `infra/platform/platform.tfvars.example` to `infra/platform/terraform.tfvars`. Replace the repository and bucket values. Copy `platform.backend.hcl.example` to `platform.backend.hcl`, with matching bucket, region, and prefix. Git ignores both local configuration files.

```powershell
terraform -chdir=infra/platform init -backend-config=platform.backend.hcl
terraform -chdir=infra/platform plan
terraform -chdir=infra/platform apply
terraform -chdir=infra/platform output
```

This creates networking, NAT gateways, an ALB, ECR, the ECS cluster, task/execution roles, logs, the deployment role, and `deployment.json` in the private state bucket. It does not create an ECS service until an image has been published by the pipeline. An empty ALB can return 503 at this stage.

If the account already has GitHub's OIDC provider, set `existing_oidc_provider_arn`; AWS permits only one provider per issuer URL. Bootstrap credentials must be able to create the ECS service-linked role if the account has not used ECS previously.

For TLS, supply an ACM certificate ARN and matching `public_hostname`, validate the certificate, and point that hostname to the ALB. Without these, this public demonstration uses HTTP and must not handle private information.

## 4. Configure GitHub

Create a GitHub environment named `production`. Limit its deployment branches to protected `main`; configure required reviewers where your repository plan supports them. Protect `main` with required validation checks and pull-request review. Environment restrictions matter because the OIDC subject is scoped to the environment, not a branch.

Set these repository Actions variables (Settings > Secrets and variables > Actions > Variables):

| Variable | Value |
| --- | --- |
| `AWS_REGION` | Region used for the platform |
| `AWS_DEPLOY_ROLE_ARN` | Terraform `deployment_role_arn` output |
| `STATE_BUCKET` | The state bucket name |
| `STATE_PREFIX` | `delivery-platform/production`, matching Terraform |
| `ENABLE_AWS_DEPLOY` | `false` initially; set to `true` when ready |

No AWS credential secrets are needed. Ensure the environment allows the repository's workflow to request an OIDC token. The CI role can publish only to this ECR repository, pass only these ECS task roles, and update only this application's service/state. It cannot provision networking or change its own IAM policy.

## 5. First delivery

Set `ENABLE_AWS_DEPLOY=true`, then push a commit to `main` or run **Validate and deliver** manually from `main`. The validate job runs first. The production job waits for configured environment approval, obtains short-lived credentials, reads platform configuration, builds/pushes an image, and applies the application Terraform stack.

The image tag combines commit SHA, run ID, and run attempt. Deployment uses the published digest, not the tag. A successful run stores `release.json` as a 30-day artifact and displays it in the workflow summary. Save the manifest for every release you may need to restore.

## 6. Verify cloud behaviour

Check that tasks have private addresses in the intended AZ subnets, ALB targets are healthy, request IDs appear in CloudWatch logs, and the live revision matches the workflow commit. Exercise a failed deployment in the sandbox and confirm ECS rollback and workflow failure detection. Test manual rollback using an earlier verified manifest. These cloud checks remain pending until actually performed.
