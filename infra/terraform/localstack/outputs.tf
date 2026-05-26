output "api_id" {
  value = aws_api_gateway_rest_api.main.id
}

output "invoke_url" {

  value = "http://localhost.localstack.cloud:${var.localstack_port}/_aws/execute-api/${aws_api_gateway_rest_api.main.id}/${var.stage_name}"

}