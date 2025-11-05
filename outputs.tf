output "api_endpoint" {
  description = "HTTP API base endpoint"
  value       = aws_apigatewayv2_api.http_api.api_endpoint
}
