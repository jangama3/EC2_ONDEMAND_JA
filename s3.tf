# Create S3 bucket for static website
resource "aws_s3_bucket" "static_website_bucket" {
  bucket = var.bucketname

  tags = {
    Name        = var.bucketname
    Environment = "Dev"
  }
}

resource "aws_s3_bucket_website_configuration" "static_website_config" {
  bucket = aws_s3_bucket.static_website_bucket.id

  index_document {
    suffix = "index.html"
  }

  error_document {
    key = "error.html" # Optional, define if you have a custom error page
  }
}

resource "aws_s3_bucket_policy" "static_website_policy" {
  bucket = aws_s3_bucket.static_website_bucket.id

  policy = jsonencode({
    Version = "2012-10-17",
    Statement = [
      {
        Sid       = "PublicReadGetObject",
        Effect    = "Allow",
        Principal = "*",
        Action    = "s3:GetObject",
        Resource = [
          "${aws_s3_bucket.static_website_bucket.arn}/*",
        ],
      },
    ],
  })
}