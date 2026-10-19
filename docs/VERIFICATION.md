# Verification scope

## Local results

| Check | Observed result |
| --- | --- |
| Python application and delivery tests | 18 passed |
| Terraform resource/provider validation | Passed for all three stacks |
| Terraform formatting | Passed |
| Mocked Terraform tests | 6 passed: state (1), platform/network (2), application (3) |
| GitHub Actions static validation | Both workflows passed actionlint, including shell checks |
| Linux Docker image and container health | Passed |
| HTTP health and baked-in revision smoke check | Passed |
| Release overview page | HTTP 200 |
| Python dependency audit | No known vulnerabilities found in the locked application requirements at validation time |

## Local checks

- Python unit tests exercise health, revision reporting, HTML escaping, response headers, image digest validation, rolling deployment verification, and refusal to accept a healthy older release.
- Docker builds run the service as a non-root user; Compose health checks and HTTP smoke tests verify the revision baked into the image.
- Terraform validation checks resource schemas for state storage, platform, and application stacks.
- Mock-provider Terraform tests check state protection, OIDC subject/audience, immutable repository settings, non-public tasks, rolling deployment controls, and rejection of mutable tags or foreign repositories.

Commands are in the README. No AWS credentials are needed for mocked Terraform tests. Dependency/provider downloads and Docker image downloads need internet access.

## Cloud acceptance: pending authorised AWS access

1. Provision the state and platform stacks in a dedicated sandbox.
2. Verify production environment restrictions and repository-scoped OIDC authentication.
3. Push a commit and confirm image publication, Terraform application, ECS rollout, and HTTP revision verification.
4. Inspect the release manifest and confirm its digest matches the deployed task definition.
5. Introduce a controlled launch/health failure and confirm circuit-breaker rollback plus a failed workflow.
6. Redeploy a prior verified manifest through the manual workflow.
7. Verify permissions deny changes to platform infrastructure and unrelated repositories/state keys.
8. Confirm cleanup and inspect billing for retained resources.

Local results do not imply that these cloud acceptance checks have passed. The repository workflow reports validation separately from the AWS delivery job. A skipped AWS job is not evidence of cloud deployment.
