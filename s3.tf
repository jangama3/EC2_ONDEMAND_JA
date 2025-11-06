
# Create the S3 bucket
resource "aws_s3_bucket" "static_website" {
  bucket        = var.bucketname
  force_destroy = true

  tags = {
    Name        = var.bucketname
    Environment = "prod"
  }
}

# Enforce bucket ownership
resource "aws_s3_bucket_ownership_controls" "ownership" {
  bucket = aws_s3_bucket.static_website.id

  rule {
    object_ownership = "BucketOwnerPreferred"
  }
}

# Configure bucket for static website hosting
resource "aws_s3_bucket_website_configuration" "website" {
  bucket = aws_s3_bucket.static_website.id

  index_document {
    suffix = "index.html"
  }

  error_document {
    key = "error.html"
  }
}
