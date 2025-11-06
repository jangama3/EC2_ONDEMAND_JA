# Write Lambda source code to a local file
resource "local_file" "lambda_src" {
  filename        = "lambda_function.py"
  file_permission = "0777"
  content         = <<-EOT
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
                instances.append({
                    "id": i["InstanceId"],
                    "name": name,
                    "state": i["State"]["Name"]
                })
        return instances

    def lambda_handler(event, context):
        # Parse API Gateway HTTP API v2 body if it exists
        body = event.get("body")
        if body:
            try:
                data = json.loads(body)
            except json.JSONDecodeError:
                return {
                    "statusCode": 400,
                    "body": json.dumps({"error": "Invalid JSON in request body"})
                }
        else:
            data = event

        action = data.get("action")
        instance_id = data.get("instance_id")

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

# Package Lambda code into a zip
data "archive_file" "lambda_zip" {
  type        = "zip"
  source_file = local_file.lambda_src.filename
  output_path = "lambda_function.zip"
}

# IAM Role for Lambda
resource "aws_iam_role" "lambda_role" {
  name = "ec2_control_lambda_role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Action    = "sts:AssumeRole"
      Effect    = "Allow"
      Principal = { Service = "lambda.amazonaws.com" }
    }]
  })
}

# IAM Policy for EC2 Access
resource "aws_iam_role_policy" "lambda_policy" {
  name = "ec2_control_policy"
  role = aws_iam_role.lambda_role.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect = "Allow"
      Action = [
        "ec2:StartInstances",
        "ec2:StopInstances",
        "ec2:DescribeInstances"
      ]
      Resource = "*"
    }]
  })
}

# Lambda Function
resource "aws_lambda_function" "ec2_control" {
  function_name    = "EC2_Control_Lambda"
  role             = aws_iam_role.lambda_role.arn
  handler          = "lambda_function.lambda_handler"
  runtime          = "python3.12"
  filename         = data.archive_file.lambda_zip.output_path
  source_code_hash = data.archive_file.lambda_zip.output_base64sha256
  timeout          = 5
}

# HTTP API
resource "aws_apigatewayv2_api" "api" {
  name          = "EC2ControlAPI"
  protocol_type = "HTTP"
}

# Lambda Integration
resource "aws_apigatewayv2_integration" "lambda_integration" {
  api_id           = aws_apigatewayv2_api.api.id
  integration_type = "AWS_PROXY"
  integration_uri  = aws_lambda_function.ec2_control.invoke_arn
}

# POST Route
resource "aws_apigatewayv2_route" "route_post" {
  api_id    = aws_apigatewayv2_api.api.id
  route_key = "POST /"
  target    = "integrations/${aws_apigatewayv2_integration.lambda_integration.id}"
}

# Stage for the API ($default)
resource "aws_apigatewayv2_stage" "stage" {
  api_id      = aws_apigatewayv2_api.api.id
  name        = "$default"
  auto_deploy = true
}

# Allow API Gateway to invoke Lambda
resource "aws_lambda_permission" "api_permission" {
  statement_id  = "AllowInvokeByAPIGateway"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.ec2_control.function_name
  principal     = "apigateway.amazonaws.com"
  source_arn    = "${aws_apigatewayv2_api.api.execution_arn}/*"
}
