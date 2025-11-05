terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
    local = {
      source = "hashicorp/local"
    }
    archive = {
      source  = "hashicorp/archive"
    }
  }
}

provider "aws" {
  region = "us-east-1"
}

############################################
# 1) Generate Lambda Source File
############################################
resource "local_file" "lambda_src" {
  filename = "lambda_function.py"

  content = <<-EOT
    import json
    import boto3

    ec2 = boto3.client("ec2")

    TAG_KEY = "Environment"
    TAG_VALUE = "Dev"

    def list_instances():
        resp = ec2.describe_instances(
            Filters=[{"Name": f"tag:{TAG_KEY}", "Values": [TAG_VALUE]}]
        )
        instances = []
        for r in resp["Reservations"]:
            for i in r["Instances"]:
                name = next((t["Value"] for t in i.get("Tags", []) if t.get("Key") == "Name"), i.get("InstanceId"))
                instances.append({"id": i["InstanceId"], "name": name, "state": i["State"]["Name"]})
        return instances

    def lambda_handler(event, context):
        action = event.get("action")
        instance_id = event.get("instance_id")

        if action == "list":
            return {"statusCode": 200, "body": json.dumps(list_instances())}

        if not instance_id:
            return {"statusCode": 400, "body": json.dumps({"error": "No instance id provided"})}

        if action == "start":
            ec2.start_instances(InstanceIds=[instance_id])
            return {"statusCode": 200, "body": json.dumps({"message": f"Started {instance_id}"})}

        if action == "stop":
            ec2.stop_instances(InstanceIds=[instance_id])
            return {"statusCode": 200, "body": json.dumps({"message": f"Stopped {instance_id}"})}

        return {"statusCode": 400, "body": json.dumps({"error": "Invalid action"})}
  EOT
}

############################################
# 2) Zip the Lambda
############################################
data "archive_file" "lambda_zip" {
  type        = "zip"
  source_file = local_file.lambda_src.filename
  output_path = "lambda_function.zip"
}

############################################
# 3) IAM Role + Permissions
############################################
resource "aws_iam_role" "lambda_role" {
  name = "EC2_Control_Lambda_Role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect = "Allow"
      Principal = { Service = "lambda.amazonaws.com" }
      Action = "sts:AssumeRole"
    }]
  })
}

resource "aws_iam_role_policy" "lambda_policy" {
  name = "EC2_Control_Lambda_Policy"
  role = aws_iam_role.lambda_role.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect = "Allow"
      Action = [
        "ec2:DescribeInstances",
        "ec2:StartInstances",
        "ec2:StopInstances"
      ]
      Resource = "*"
    }]
  })
}

############################################
# 4) Lambda Function
############################################
resource "aws_lambda_function" "ec2_control" {
  function_name = "EC2_Control_Lambda"
  role          = aws_iam_role.lambda_role.arn
  handler       = "lambda_function.lambda_handler"
  runtime       = "python3.12"
  filename      = data.archive_file.lambda_zip.output_path
  timeout       = 5
}

############################################
# 5) API Gateway HTTP API
############################################
resource "aws_apigatewayv2_api" "api" {
  name          = "EC2ControlAPI"
  protocol_type = "HTTP"
}

resource "aws_apigatewayv2_integration" "lambda_integration" {
  api_id                 = aws_apigatewayv2_api.api.id
  integration_type       = "AWS_PROXY"
  integration_uri        = aws_lambda_function.ec2_control.invoke_arn
  payload_format_version = "2.0"
}

resource "aws_apigatewayv2_route" "route" {
  api_id    = aws_apigatewayv2_api.api.id
  route_key = "POST /"
  target    = "integrations/${aws_apigatewayv2_integration.lambda_integration.id}"
}

resource "aws_lambda_permission" "apigw" {
  statement_id  = "AllowAPIGatewayInvoke"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.ec2_control.function_name
  principal     = "apigateway.amazonaws.com"
  source_arn    = "${aws_apigatewayv2_api.api.execution_arn}/*/*"
}

############################################
# 6) Output API Endpoint
############################################
output "api_endpoint" {
  value = aws_apigatewayv2_api.api.api_endpoint
}
