# CI/CD Pipeline Documentation

> **Note**: For manual deployment and initial setup, see [DEPLOYMENT.md](DEPLOYMENT.md). This guide covers automated CI/CD workflows.

## Overview

This project uses **five separate GitHub Actions workflows** for complete automation:

1. **Pull Request Checks** (`.github/workflows/pr-checks.yml`) - Validates PRs
2. **Reusable Build** (`.github/workflows/reusable-build.yml`) - Shared test/build logic between dev and production
3. **Dev Deployment** (`.github/workflows/dev.yml`) - Deploys to dev
4. **Production Deployment** (`.github/workflows/production.yml`) - Deploys to production
5. **Terraform Infrastructure** (`.github/workflows/terraform.yml`) - Manages AWS infrastructure

---

## Workflow 1: Pull Request Checks

### Purpose
Validates code quality and security on pull requests without deploying.

### Triggers
- Pull requests to `main` or `dev` branches

### Jobs
- **test**: Runs unit tests, linting, code coverage
- **security-scan**: Scans for vulnerabilities with Trivy

### Usage
```bash
# Create PR
git checkout -b feature/new-sensor
git push origin feature/new-sensor
# Create PR on GitHub - checks run automatically
```

---

## Workflow 2: Reusable Build

### Purpose
Shared workflow for testing, security scanning, and building Docker images. Called by dev.yml and production.yml to avoid code duplication (DRY principle).

### Jobs
1. **test**: Unit tests, linting, code coverage
2. **security-scan**: Trivy vulnerability scanning
3. **build**: Docker image build and push to ECR

### Usage
This workflow is not triggered directly - it's called by other workflows using `workflow_call`.

---

## Workflow 3: Dev Deployment

### Purpose
Builds and deploys application to dev environment.

### Triggers
- Push to `dev` branch

### Jobs
1. **build**: Calls reusable-build.yml
2. **deploy**: Deploy to dev EKS cluster

### Usage
```bash
# Push to dev
git checkout dev
git merge feature/new-sensor
git push origin dev
# Automatic deployment to dev
```

---

## Workflow 4: Production Deployment

### Purpose
Builds and deploys application to production (multi-region).

### Triggers
- Push to `main` branch

### Jobs
1. **build**: Calls reusable-build.yml
2. **deploy**: Deploy to production EKS clusters (eu-central-1, eu-west-1)

### Approval Required
- Manual approval via GitHub environment protection

### Usage
```bash
# Push to main
git checkout main
git merge dev
git push origin main
# Approve deployment in GitHub Actions UI
```

---

## Workflow 5: Terraform Infrastructure

### Purpose
Manages AWS infrastructure (VPC, EKS, SQS, S3, DynamoDB) using Terraform.

### Triggers

**Automatic:**
- Push to `main` branch with changes in `infrastructure/terraform/**`
- Pull requests to `main` with Terraform changes

**Manual:**
- GitHub Actions UI → "Run workflow" button
- Choose environment (dev/production)
- Choose action (plan/apply/destroy)

### Jobs

#### 1. `terraform-plan`
- Validates Terraform code
- Creates execution plan
- Uploads plan as artifact

#### 2. `terraform-apply-dev`
- Runs automatically on push to `main`
- Applies changes to dev environment

#### 3. `terraform-apply-production`
- Runs only via manual workflow dispatch
- Requires manual approval
- Applies changes to production environment

### Setup

> **Prerequisites**: Complete the one-time setup in [DEPLOYMENT.md](DEPLOYMENT.md) first (Terraform backend, ECR repository).

#### Step 1: Configure GitHub Secrets

Navigate to: **Settings → Secrets and variables → Actions**

Add secret:
```
AWS_ROLE_ARN: arn:aws:iam::ACCOUNT_ID:role/GitHubActionsRole
```

See [OIDC_SETUP.md](OIDC_SETUP.md) for creating the IAM role.

#### Step 2: Configure GitHub Environments

Navigate to: **Settings → Environments**

Create environments:

**dev-infrastructure:**
- Protection rules: None (auto-deploy)

**production-infrastructure:**
- Protection rules: ✅ Required reviewers

---

## Complete Deployment Flow

### Development Workflow

```
1. Create feature branch
   git checkout -b feature/new-sensor

2. Make changes and push
   git push origin feature/new-sensor

3. Create PR to dev
   → pr-checks.yml runs (test + security scan)

4. Merge PR to dev
   → dev.yml runs (build + deploy to dev)

5. Test in dev
   QUEUE_URL=<dev-url> ./scripts/send_test_messages.sh

6. Create PR from dev to main
   → pr-checks.yml runs

7. Merge to main
   → production.yml runs (build + deploy to production)
   → Requires manual approval

8. Approve and deploy
   → Multi-region deployment
```

---

## Summary

| Workflow | Trigger | Environment | Approval Required |
|----------|---------|-------------|-------------------|
| PR Checks | Pull request | N/A | No |
| Reusable Build | Called by other workflows | N/A | No |
| Dev | Push to dev | dev | No |
| Production | Push to main | production | Yes |
| Terraform (Dev) | Push to main | dev | No |
| Terraform (Production) | Manual | production | Yes |

**Separated workflows for better maintainability and security.**
