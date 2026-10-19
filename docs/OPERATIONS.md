# Delivery operations

## Deployment ownership

Platform changes use the platform Terraform stack with an authorised infrastructure identity. Application releases use the application Terraform stack via GitHub's deployment identity. Never run `aws ecs update-service` as a normal delivery step: it would create drift from the Terraform-managed task definition.

Release and manual rollback workflows use the same concurrency group, with cancellation disabled for the running job. GitHub concurrency is not a durable FIFO queue and may replace pending runs; this project delivers the latest eligible commit rather than guaranteeing every intermediate commit is deployed. S3 locks protect Terraform state. Do not cancel a Terraform apply or force-unlock a live operation without first investigating it.

## Redeploy an earlier release

Download a previously successful `release.json` artifact. From its `image_uri`, take the `sha256:...` digest and its `revision` field. Run **Redeploy a verified release** on `main`, supplying those two values. It uses the current approved deployment code to apply the prior image through Terraform, then checks ECS and the image's baked-in revision.

This workflow only accepts a digest within the platform's ECR repository. It does not recreate an image from old source. Retain tagged release images for the recovery window; the ECR lifecycle policy removes only untagged images. Protect workflow files and the production environment with review.

## Failed delivery

ECS's circuit breaker can roll back to a previously completed deployment. The first-ever deployment has no healthy predecessor. Previous task definition revisions are retained (`skip_destroy`) so they remain available to ECS rollback; prune unused revisions separately after the recovery window. A service can become stable on an older image; the verification script explicitly rejects that as a successful new release. A failed Terraform apply or a failed post-deployment check is shown as a failed workflow, and no verified manifest is produced.

A post-deployment HTTP/revision failure does not itself trigger an automatic Terraform rollback. Inspect service events and logs, then redeploy the last known good digest through the manual workflow. After any ECS automatic rollback, Terraform's next refresh and plan must be reviewed and reconciled through another application apply.

Inspect `/ecs/delivery-platform` in CloudWatch and ECS service events. Image-pull failures commonly involve a missing image, task execution permissions, or private subnet NAT access. OIDC denial commonly means the repository/environment does not match the IAM trust policy. Backend denial commonly means the state bucket, prefix, or region differs from the provisioned values.

The artifact contains release metadata only. Do not upload Terraform state or saved binary plans as public artifacts. Plans and generated release tfvars are deleted by the deployment script after an apply attempt. Credentials are supplied by OIDC and never written into project files.

## Cleanup

Disable `ENABLE_AWS_DEPLOY` first and wait for running jobs to finish. Using an authorised operator identity, initialise the application backend with the same bucket/prefix and supply the last image URI plus platform configuration as variables. Review and destroy the application stack first. For example, download `deployment.json` and a verified `release.json`, then prepare the application variables:

```powershell
aws s3 cp s3://YOUR_BUCKET/delivery-platform/production/deployment.json platform.json
python -c 'import json; c=json.load(open("platform.json")); r=json.load(open("release.json")); json.dump({"region":c["region"],"platform":c,"image_uri":r["image_uri"]},open("infra/application/release.auto.tfvars.json","w"))'
terraform -chdir=infra/application init -reconfigure -backend-config="bucket=YOUR_BUCKET" -backend-config="key=delivery-platform/production/application.tfstate" -backend-config="region=us-east-1" -backend-config="encrypt=true" -backend-config="use_lockfile=true"
terraform -chdir=infra/application plan -destroy
terraform -chdir=infra/application destroy
```

Delete the local release tfvars after cleanup. If no verified release exists, use the attempted image digest from the workflow and the deployment configuration rather than a success manifest.

Then empty the ECR repository after retaining any images you need and destroy the platform stack. NAT gateways and the ALB continue to incur charges until removed. The state bucket is intentionally protected; retain its history according to your policy. Check for remaining images, logs, public IP allocations, and state artifacts. Stopping the local Compose container does not stop AWS resources.
