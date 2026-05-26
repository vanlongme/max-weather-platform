# cosign-signing.tf — KMS asymmetric signing key for cosign image signing
# Key type: ECC_NIST_P256 (required by cosign; symmetric keys cannot be used)
# Key rotation: DISABLED — KMS does not support rotation on asymmetric keys
resource "aws_kms_key" "cosign_signer" {
  description              = "${var.name} cosign image signing key"
  customer_master_key_spec = "ECC_NIST_P256"
  key_usage                = "SIGN_VERIFY"
  enable_key_rotation      = false # Must be false for asymmetric keys
  deletion_window_in_days  = 30
  tags = merge(var.tags, {
    Name = "${var.name}-cosign-signer"
  })
}

resource "aws_kms_alias" "cosign_signer" {
  name          = "alias/max-weather-cosign-signer"
  target_key_id = aws_kms_key.cosign_signer.key_id
}

resource "aws_iam_policy" "cosign_kms" {
  name        = "${var.name}-cosign-kms-policy"
  description = "Allows cosign to sign/verify images using the ${var.name} KMS signing key"
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "CosignKMSAccess"
        Effect = "Allow"
        Action = [
          "kms:Sign",
          "kms:GetPublicKey",
          "kms:DescribeKey",
          "kms:Verify",
        ]
        Resource = aws_kms_key.cosign_signer.arn
      },
    ]
  })
  tags = merge(var.tags, {
    Name = "${var.name}-cosign-kms-policy"
  })
}
