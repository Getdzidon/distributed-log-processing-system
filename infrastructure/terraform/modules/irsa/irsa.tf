# IAM Roles for Service Accounts (IRSA)
# Allows Kubernetes pods to assume IAM roles without storing credentials
# Uses OIDC provider to establish trust between EKS and IAM

# Trust policy allowing EKS service account to assume this role
data "aws_iam_policy_document" "assume_role" {
  statement {
    actions = ["sts:AssumeRoleWithWebIdentity"]
    
    principals {
      type        = "Federated"
      identifiers = [var.oidc_provider_arn]
    }
    
    # Only allow specific service account in specific namespace
    condition {
      test     = "StringEquals"
      variable = "${replace(var.oidc_provider_arn, "/^(.*provider/)/", "")}:sub"
      values   = ["system:serviceaccount:${var.namespace}:${var.service_account_name}"]
    }
  }
}

# IAM role that pods will assume
resource "aws_iam_role" "service_account" {
  name               = "${var.cluster_name}-${var.service_account_name}"
  assume_role_policy = data.aws_iam_policy_document.assume_role.json
}

# IAM policy with permissions for SQS, S3, and DynamoDB
resource "aws_iam_policy" "service_account" {
  name = "${var.cluster_name}-${var.service_account_name}-policy"
  
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "sqs:ReceiveMessage",
          "sqs:DeleteMessage",
          "sqs:GetQueueAttributes"
        ]
        Resource = var.sqs_queue_arn
      },
      {
        Effect = "Allow"
        Action = [
          "s3:PutObject",
          "s3:GetObject"
        ]
        Resource = "${var.s3_bucket_arn}/*"
      },
      {
        Effect = "Allow"
        Action = [
          "dynamodb:PutItem",
          "dynamodb:GetItem",
          "dynamodb:Query"
        ]
        Resource = var.dynamodb_table_arn
      }
    ]
  })
}

# Attach policy to role
resource "aws_iam_role_policy_attachment" "service_account" {
  role       = aws_iam_role.service_account.name
  policy_arn = aws_iam_policy.service_account.arn
}
