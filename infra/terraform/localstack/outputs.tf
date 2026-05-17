output "api_id" {
  value = aws_api_gateway_rest_api.main.id
}

output "invoke_url" {

  value = "http://localhost.localstack.cloud:4566/restapis/${aws_api_gateway_rest_api.main.id}/${var.stage_name}/_user_request_"

}