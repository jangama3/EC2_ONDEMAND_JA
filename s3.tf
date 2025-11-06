# Create S3 bucket for static website
resource "aws_s3_bucket" "staticwebsiterraform" {
  bucket = var.bucketname

  tags = {
    Name        = var.bucketname
    Environment = "Dev"
  }
}

# Ensure bucket ownership
resource "aws_s3_bucket_ownership_controls" "ownership" {
  bucket = aws_s3_bucket.staticwebsiterraform.id

  rule {
    object_ownership = "BucketOwnerPreferred"
  }
}

# Configure public access (allows public-read)
resource "aws_s3_bucket_public_access_block" "publicaccess" {
  bucket = aws_s3_bucket.staticwebsiterraform.id

  block_public_acls       = false
  block_public_policy     = false
  ignore_public_acls      = false
  restrict_public_buckets = false
}

# Set bucket ACL
resource "aws_s3_bucket_acl" "acl" {
  depends_on = [
    aws_s3_bucket_ownership_controls.ownership,
    aws_s3_bucket_public_access_block.publicaccess,
  ]

  bucket = aws_s3_bucket.staticwebsiterraform.id
  acl    = "public-read"
}

# Upload index.html manually (ensure file exists in repo)

resource "aws_s3_object" "index" {
  bucket       = aws_s3_bucket.staticwebsiterraform.id
  key          = "index.html"
  source       = "index.html"
  acl          = "public-read"
  content_type = "text/html"
}

resource "aws_s3_object" "error" {
  bucket       = aws_s3_bucket.staticwebsiterraform.id
  key          = "error.html"
  source       = "error.html"
  acl          = "public-read"
  content_type = "text/html"
}

# Upload error.html manually (optional)

# Enable static website hosting
resource "aws_s3_bucket_website_configuration" "website" {
  bucket = aws_s3_bucket.staticwebsiterraform.id

  index_document {
    suffix = "index.html"
  }

  error_document {
    key = "error.html"
  }

  depends_on = [aws_s3_bucket_acl.acl]
}
