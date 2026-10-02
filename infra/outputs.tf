output "api_url" {
  description = "Base URL for the HTTP API"
  value       = aws_apigatewayv2_stage.default.invoke_url
}

output "orders_table" { value = aws_dynamodb_table.orders.name }
output "dead_letter_queue" { value = aws_sqs_queue.orders_dlq.url }

output "dashboard_url" {
  description = "Public HTTPS URL for the deployed CloudOrder dashboard"
  value       = "https://${aws_cloudfront_distribution.web.domain_name}"
}
