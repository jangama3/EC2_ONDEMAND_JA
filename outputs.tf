output "api_endpoint" {
  description = "Invoke URL for the API"
  value       = aws_apigatewayv2_api.api.api_endpoint
}
