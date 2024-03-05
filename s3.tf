resource "aws_s3_bucket" "backend" {
  count  = var.create_vpc ? 1 : 0
  bucket = "group2-${lower(var.env)}-${random_integer.backend.result}"

  tags = {
    Name        = "My backend"
    Environment = "Dev"
  }

  versioning {
    enabled = true
  }

  lifecycle_rule {
    id      = "example-lifecycle-rule"
    enabled = true

    expiration {
      days = 30
    }
  }

}

resource "aws_iam_role" "replication_role" {
  name = "s3-replication-role"
  assume_role_policy = jsonencode({
    Version = "2012-10-17",
    Statement = [{
      Effect = "Allow",
      Principal = {
        Service = "s3.amazonaws.com"
      },
      Action = "sts:AssumeRole"
    }]
  })
}

#kms key for bucket encryption
resource "aws_kms_key" "my_key" {
  description             = "This key is used to encrypt bucket objects"
  deletion_window_in_days = 10
  enable_key_rotation     = true
  policy                  = <<POLICY
{
  "Version": "2012-10-17",
  "Id": "key-consolepolicy-3",
  "Statement": [
    {
      "Sid": "Enable IAM User Permissions",
      "Effect": "Allow",
      "Principal": {
          "AWS": "arn:aws:iam::657678360112:root"  
        },
      "Action": "kms:*",
      "Resource": "*"
    }
  ]
}
POLICY
}

resource "aws_s3_bucket_server_side_encryption_configuration" "example" {
  bucket = aws_s3_bucket.backend[0].id
  rule {
    apply_server_side_encryption_by_default {
      kms_master_key_id = aws_kms_key.my_key.arn
      sse_algorithm     = "aws:kms"
    }
  }
}

#Random integer for bucket naming convention
resource "random_integer" "backend" {
  min = 1
  max = 100
  keepers = {
    Environment = var.env
  }
}

#versioning
resource "aws_s3_bucket_versioning" "versioning_example" {
  bucket = aws_s3_bucket.backend[0].id
  versioning_configuration {
    status = "Enabled"
  }
}

# Public access block
resource "aws_s3_bucket_public_access_block" "access_block" {
  bucket                  = aws_s3_bucket.backend[0].id
  block_public_acls       = true
  block_public_policy     = true
  restrict_public_buckets = true
  ignore_public_acls      = true
}

resource "aws_s3_bucket_lifecycle_configuration" "bucket-config" {
  bucket = aws_s3_bucket.backend[0].id

  rule {
    id = "abort_failed_uploads"
    abort_incomplete_multipart_upload {
      days_after_initiation = 7
    }
    filter {}
    status = "Enabled"
  }

  rule {
    id = "log"
    expiration {
      days = 90
    }
    filter {
      and {
        prefix = "log/"
        tags = {
          rule      = "log"
          autoclean = "true"
        }
      }
    }
    status = "Enabled"
    transition {
      days          = 30
      storage_class = "STANDARD_IA"
    }
    transition {
      days          = 60
      storage_class = "GLACIER"
    }
  }

  rule {
    id = "tmp"
    filter {
      prefix = "tmp/"
    }
    expiration {
      date = "2025-01-13T00:00:00Z"
    }
    status = "Enabled"
  }
}

resource "aws_s3_bucket_logging" "example" {
  bucket        = "replication-s3-group2"
  target_bucket = "replication-s3-group2"
  target_prefix = "logs/"
}


resource "aws_s3_bucket_lifecycle_configuration" "pass" {
  bucket = aws_s3_bucket.backend[0].id
  rule {
    abort_incomplete_multipart_upload {
      days_after_initiation = 7
    }
    filter {}
    id     = "log"
    status = "Enabled"
  }
}
