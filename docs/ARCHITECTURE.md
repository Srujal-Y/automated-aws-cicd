# Architecture and delivery decisions

## Separation of responsibilities

| Component | Owner | Reason |
| --- | --- | --- |
| State storage | Bootstrap operator | Bucket exists before remote Terraform backends |
| VPC, ALB, cluster, ECR, roles, logs | Platform Terraform stack | Infrastructure changes have a separate review boundary |
| Task definition and ECS service | Application Terraform stack | Every image update is reflected in Terraform state |
| Image publication and release checks | GitHub Actions | Builds are traceable to source and verified before recording success |

The pipeline reads a narrow configuration object from S3 rather than reading the complete platform state. Its permissions do not include the platform state object. Application state has an independent lock file and key.

## Availability and isolation

The VPC has public ALB/NAT subnets and private task subnets in two AZs. Private tasks have no public IPs. Only the ALB can reach TCP 8000 on tasks; outbound access is limited to HTTPS. Two tasks run during steady state. A rolling deployment keeps the configured healthy capacity while allowing temporary surge tasks. ECS and ALB process checks are both configured.

The application is stateless and contains no customer data or database. This project demonstrates delivery mechanics independently from the Three Tier project's persistence architecture.

## Identity and integrity

The production job receives short-lived AWS credentials through GitHub OIDC. Trust checks both the AWS STS audience and the exact repository/environment subject. GitHub environment deployment-branch controls are required to bind production to reviewed `main` code. The role cannot change IAM, the VPC, the ALB, or the platform state.

Immutable ECR tags prevent replacement of a published tag. The pipeline deploys the digest returned by the build action and checks the Git SHA embedded in the image, independent of runtime Terraform variables. Build provenance and an SBOM are requested from BuildKit. ECR scan-on-push is enabled; scan findings are not currently an enforced release gate.

## Recovery and honest success criteria

ECS circuit-breaker rollback protects against launch and health-check failures when a previous completed deployment exists. Stability alone is insufficient: the pipeline also checks the primary task definition, completed rollout, running capacity, and HTTP revision. Application-level failures after successful deployment require operator-directed rollback through the manual workflow.

## Trade-offs and production extensions

Two NAT gateways improve AZ independence at a higher baseline cost. A small CPU/memory task size is suitable for this demonstration and needs load testing for a real workload. HTTP is supported for the public demo; require HTTPS for sensitive applications. The ECS container has a writable filesystem to accommodate Gunicorn temporary files, but runs as a non-root user with all capabilities dropped; local Compose additionally exercises a read-only filesystem with `/tmp` mounted separately.

Add an approved vulnerability release gate, action pinning to audited commit SHAs, central access/audit logs, alarm routing, workload-specific authentication, measured SLOs, and protected change approvals before production use. Customer-facing banking requirements, compliance certification, penetration testing, and resilience guarantees are outside the verified scope.

GitHub-hosted CI and AWS behaviour have to be observed in their real environments. Mocked Terraform tests validate configuration intent, not AWS reachability, IAM enforcement, or live rolling deployment behaviour.
