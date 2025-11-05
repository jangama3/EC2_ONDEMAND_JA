provider "aws" {
  region = var.region
}

# write the lambda source file locally
resource "local_file" "lambda_src" {
  filename = "${path.module}/lambda_function.py"
  content  = <<'PY'
import json
import boto3
import os

ec2 = boto3.client("ec2", region_name=os.getenv("AWS_REGION", "us-east-1"))

TAG_KEY = os.getenv("TAG_KEY", "Environment")
TAG_VALUE = os.getenv("TAG_VALUE", "Dev")

def _has_allowed_tag(instance):
    for t in instance.get("Tags", []):
        if t.get("Key") == TAG_KEY and t.get("Value") == TAG_VALUE:
            return True
    return False

def list_instances():
    resp = ec2.describe_instances(
        Filters=[{"Name": f"tag:{TAG_KEY}", "Values": [TAG_VALUE]},
                 {"Name": "instance-state-name", "Values": ["running", "stopped"]}]
    )
    instances = []
    for r in resp.get("Reservations", []):
        for i in r.get("Instances", []):
            name = next((t["Value"] for t in i.get("Tags", []) if t.get("Key") == "Name"), i.get("InstanceId"))
            instances.append({
                "InstanceId": i.get("InstanceId"),
                "State": i.get("State", {}).get("Name"),
                "Name": name
            })
    return instances

def get_instance(instance_id):
    resp = ec2.describe_instances(InstanceIds=[instance_id])
    for r in resp.get("Reservations", []):
        for i in r.get("Instances", []):
            return i
    return None

def start_instance(instance_id):
    ec2.start_instances(InstanceIds=[instance_id])

def stop_instance(instance_id):
    ec2.stop_instances(InstanceIds=[instance_id])

def lambda_handler(event, context):
    # Debugging log (appears in CloudWatch)
    print("EVENT:", json.dumps(event))

    try:
        method = event.get("requestContext", {}).get("http", {}).get("method")
        raw_path = event.get("rawPath", "")

        # GET /list
        if method == "GET" and raw_path == "/list":
            instances = list_instances()
            return {
                "statusCode": 200,
                "headers": {"Content-Type": "application/json", "Access-Control-Allow-Origin": "*"},
                "body": json.dumps(instances)
            }

        # POST /start/{id}
        if method == "POST" and raw_path.startswith("/start/"):
            instance_id = raw_path.split("/start/")[1]
            if not instance_id:
                return {"statusCode": 400, "body": json.dumps({"error": "No instance id provided"})}

            inst = get_instance(instance_id)
            if not inst:
                return {"statusCode": 404, "body": json.dumps({"error": "Instance not found"})}
            if not _has_allowed_tag(inst):
                return {"statusCode": 403, "body": json.dumps({"error": "Not allowed to control this instance"})}

            start_instance(instance_id)
            return {"statusCode": 200, "headers": {"Access-Control-Allow-Origin": "*"}, "body": json.dumps({"message": f"Starting {instance_id}"})}

        # POST /stop/{id}
        if method == "POST" and raw_path.startswith("/stop/"):
            instance_id = raw_path.split("/stop/")[1]
            if not instance_id:
                return {"statusCode": 400, "body": json.dumps({"error": "No instance id provided"})}

            inst = get_instance(instance_id)
            if not inst:
                return {"statusCode": 404, "body": json.dumps({"error": "Instance not found"})}
            if not _has_allowed_tag(inst):
                return {"statusCode": 403, "body": json.dumps({"error": "Not allowed to control this instance"})}

            stop_instance(instance_id)
            return {"statusCode": 200, "headers": {"Access-Control-Allow-Origin": "*"}, "body": json.dumps({"message": f"Stopping {instance_id}"})}

        return {"statusCode": 405, "body": json.dumps({"error": "Method not allowed"})}

    except Exception as e:
        print("ERROR:", str(e))
        return {"statusCode": 500, "body": json.dumps({"error": str(e)})}
PY
}

# zip the lambda code
data "archive_file" "lambda_zip" {
  type        = "zip"
  source_file = local_file.lambda_src.filename
  output_path = "${path.module}/lambda_function.zip"
}

# IAM role for lambda
data "aws_iam_policy_document" "lambda_assume" {
  statement {
    actions = ["sts:AssumeRole"]
    principals {
      type        = "Service"
      identifiers = ["lambda.amazonaws.com"]
    }
  }
}

resource "aws_iam_role" "lambda_role" {
  name               = "${var.lambda_name}-role"
  assume_role_policy = data.aws_iam_policy_document.lambda_assume.json
}

resource "aws_iam_policy" "lambda_policy" {
  name = "${var.lambda_name}-policy"

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "ec2:DescribeInstances",
          "ec2:StartInstances",
          "ec2:StopInstances"
        ]
        Resource = "*"
      },
      {
        Effect = "Allow"
        Action = [
          "logs:CreateLogGroup",
          "logs:CreateLogStream",
          "logs:PutLogEvents"
        ]
        Resource = "*"
      }
    ]
  })
}

resource "aws_iam_role_policy_attachment" "attach_policy" {
  role       = aws_iam_role.lambda_role.name
  policy_arn = aws_iam_policy.lambda_policy.arn
}

# create lambda
resource "aws_lambda_function" "ec2_control" {
  function_name = var.lambda_name
  filename      = data.archive_file.lambda_zip.output_path
  source_code_hash = data.archive_file.lambda_zip.output_base64sha256
  handler       = "lambda_function.lambda_handler"
  runtime       = "python3.13"
  role          = aws_iam_role.lambda_role.arn
  publish       = true
  environment {
    variables = {
      TAG_KEY   = var.tag_key
      TAG_VALUE = var.tag_value
    }
  }
  # give a slightly longer timeout for ec2 operations
  timeout = 10
}

# Create HTTP API
resource "aws_apigatewayv2_api" "http_api" {
  name          = "ec2-control-api"
  protocol_type = "HTTP"
}

# create integration (Lambda proxy)
resource "aws_apigatewayv2_integration" "lambda_integ" {
  api_id                 = aws_apigatewayv2_api.http_api.id
  integration_type       = "AWS_PROXY"
  integration_uri        = aws_lambda_function.ec2_control.arn
  integration_method     = "POST"
  payload_format_version = "2.0"
}

# routes
resource "aws_apigatewayv2_route" "list_route" {
  api_id    = aws_apigatewayv2_api.http_api.id
  route_key = "GET /list"
  target    = "integrations/${aws_apigatewayv2_integration.lambda_integ.id}"
}

resource "aws_apigatewayv2_route" "start_route" {
  api_id    = aws_apigatewayv2_api.http_api.id
  route_key = "POST /start/{id}"
  target    = "integrations/${aws_apigatewayv2_integration.lambda_integ.id}"
}

resource "aws_apigatewayv2_route" "stop_route" {
  api_id    = aws_apigatewayv2_api.http_api.id
  route_key = "POST /stop/{id}"
  target    = "integrations/${aws_apigatewayv2_integration.lambda_integ.id}"
}

# default stage with auto-deploy
resource "aws_apigatewayv2_stage" "default" {
  api_id      = aws_apigatewayv2_api.http_api.id
  name        = "$default"
  auto_deploy = true
}

# permission for API Gateway to invoke Lambda
resource "aws_lambda_permission" "apigw" {
  statement_id  = "AllowAPIGatewayInvoke"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.ec2_control.function_name
  principal     = "apigateway.amazonaws.com"
  source_arn    = "${aws_apigatewayv2_api.http_api.execution_arn}/*/*"
}

# outputs
output "api_url" {
  description = "Base URL for the HTTP API"
  value       = aws_apigatewayv2_api.http_api.api_endpoint
}

output "lambda_name" {
  value = aws_lambda_function.ec2_control.function_name
}
