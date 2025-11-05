resource "local_file" "lambda_src" {
  filename = "lambda_function.py"
  content  = <<-PY
import json
import boto3
import os

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

def get_instance(instance_id):
    resp = ec2.describe_instances(InstanceIds=[instance_id])
    for r in resp["Reservations"]:
        for i in r["Instances"]:
            return i
    return None

def lambda_handler(event, context):
    print("EVENT:", json.dumps(event))

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
PY
}

# --- Lambda Role ---
resource "aws_iam_role" "lambda_role" {
  name = "ec2_control_lambda_role"

  assume_role_policy = <<-EOF
{
  "Version": "2012-10-17",
  "Statement": [{
    "Effect": "Allow",
    "Principal": {"Service": "lambda.amazonaws.com"},
    "Action": "sts:AssumeRole"
  }]
}
EOF
}

resource "aws_iam_role_policy" "lambda_policy" {
  name = "ec2_control_policy"
  role = aws_iam_role.lambda_role.id

  policy = <<-EOF
{
  "Version": "2012-10-17",
  "Statement": [{
    "Effect": "Allow",
    "Action": [
      "ec2:StartInstances",
      "ec2:StopInstances",
      "ec2:DescribeInstances"
    ],
    "Resource": "*"
  }]
}
EOF
}

# --- Lambda Function ---
resource "aws_lambda_function" "ec2_control" {
  function_name = "EC2_Control_Lambda"
  role          = aws_iam_role.lambda_role.arn
  handler       = "lambda_function.lambda_handler"
  runtime       = "python3.12"
  filename      = local_file.lambda_src.filename
}

# --- API Gateway ---
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

resource "aws_lambda_permission" "api_lambda_permission" {
  statement_id  = "AllowAPIGatewayInvoke"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.ec2_control.function_name
  principal     = "apigateway.amazonaws.com"
  source_arn    = "${aws_apigatewayv2_api.api.execution_arn}/*/*"
}

output "api_url" {
  value = aws_apigatewayv2_api.api.api_endpoint
}