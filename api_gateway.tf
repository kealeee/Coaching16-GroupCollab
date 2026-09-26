# ==============================================================================
# DATA LOOKUPS: Dynamic SSL Certificate and DNS Zones
# ==============================================================================
# Dynamically finds the pre-existing ACM certificate for the sandbox domain
data "aws_acm_certificate" "sandbox_cert" {
  domain   = "*.sctp-sandbox.com"
  statuses = ["ISSUED"]
}

# Dynamically finds the Route 53 Hosted Zone for the sandbox environment
data "aws_route53_zone" "sandbox_zone" {
  name         = "sctp-sandbox.com."
  private_zone = false
}

# ==============================================================================
# 1. Core REST API Gateway
# ==============================================================================
resource "aws_api_gateway_rest_api" "api" {
  name        = "kean-url-shortener-api"
  description = "Serverless URL Shortener API Gateway for group project"

  endpoint_configuration {
    types = ["REGIONAL"]
  }
}

# ==============================================================================
# INPUT VARIABLES: Cross-Team Integration (KeanHin Links)
# ==============================================================================
variable "create_lambda_arn" {
  type        = string
  description = "ARN of the create-url Lambda provided by KeanHin"
}

variable "retrieve_lambda_arn" {
  type        = string
  description = "ARN of the retrieve-url Lambda provided by KeanHin"
}

variable "create_lambda_name" {
  type        = string
  description = "Function name of the create-url Lambda for KeanHin's mapping"
}

variable "retrieve_lambda_name" {
  type        = string
  description = "Function name of the retrieve-url Lambda for KeanHin's mapping"
}

# ==============================================================================
# POST ROUTE: /newurl
# ==============================================================================
resource "aws_api_gateway_resource" "newurl" {
  rest_api_id = aws_api_gateway_rest_api.api.id
  parent_id   = aws_api_gateway_rest_api.api.root_resource_id
  path_part   = "newurl"
}

resource "aws_api_gateway_method" "post_method" {
  rest_api_id   = aws_api_gateway_rest_api.api.id
  resource_id   = aws_api_gateway_resource.newurl.id
  http_method   = "POST"
  authorization = "NONE"
}

resource "aws_api_gateway_integration" "post_integration" {
  rest_api_id             = aws_api_gateway_rest_api.api.id
  resource_id             = aws_api_gateway_resource.newurl.id
  http_method             = aws_api_gateway_method.post_method.http_method
  integration_http_method = "POST"
  type                    = "AWS_PROXY"
  uri                     = var.create_lambda_arn
}

resource "aws_api_gateway_method_response" "response_200" {
  rest_api_id = aws_api_gateway_rest_api.api.id
  resource_id = aws_api_gateway_resource.newurl.id
  http_method = aws_api_gateway_method.post_method.http_method
  status_code = "200"

  response_models = {
    "application/json" = "Empty"
  }
}

# ==============================================================================
# GET ROUTE: /{shortid}
# ==============================================================================
resource "aws_api_gateway_resource" "geturl" {
  rest_api_id = aws_api_gateway_rest_api.api.id
  parent_id   = aws_api_gateway_rest_api.api.root_resource_id
  path_part   = "{shortid}"
}

resource "aws_api_gateway_method" "get_method" {
  rest_api_id   = aws_api_gateway_rest_api.api.id
  resource_id   = aws_api_gateway_resource.geturl.id
  http_method   = "GET"
  authorization = "NONE"
}

resource "aws_api_gateway_integration" "get_integration" {
  rest_api_id             = aws_api_gateway_rest_api.api.id
  resource_id             = aws_api_gateway_resource.geturl.id
  http_method             = aws_api_gateway_method.get_method.http_method
  integration_http_method = "POST"
  type                    = "AWS"
  uri                     = var.retrieve_lambda_arn

  request_templates = {
    "application/json" = <<EOF
{
  "short_id": "$input.params('shortid')"
}
EOF
  }
}

resource "aws_api_gateway_method_response" "response_302" {
  rest_api_id = aws_api_gateway_rest_api.api.id
  resource_id = aws_api_gateway_resource.geturl.id
  http_method = aws_api_gateway_method.get_method.http_method
  status_code = "302"

  response_parameters = {
    "method.response.header.Location" = true
  }
}

resource "aws_api_gateway_integration_response" "get_integration_response" {
  rest_api_id = aws_api_gateway_rest_api.api.id
  resource_id = aws_api_gateway_resource.geturl.id
  http_method = aws_api_gateway_method.get_method.http_method
  status_code = aws_api_gateway_method_response.response_302.status_code

  response_parameters = {
    "method.response.header.Location" = "integration.response.body.location"
  }

  depends_on = [
    aws_api_gateway_integration.get_integration
  ]
}

# ==============================================================================
# ROUTE53 CUSTOM DOMAIN MAPPING (Variable-Driven Block)
# ==============================================================================
resource "aws_api_gateway_domain_name" "shortener" {
  domain_name              = var.custom_domain_name # Referenced from variables.tf
  regional_certificate_arn = data.aws_acm_certificate.sandbox_cert.arn

  endpoint_configuration {
    types = ["REGIONAL"]
  }
}

# DNS Record Alias link to connect traffic to the Gateway endpoint
resource "aws_route53_record" "www" {
  name    = var.custom_domain_name # Referenced from variables.tf
  type    = "A"
  zone_id = data.aws_route53_zone.sandbox_zone.zone_id

  alias {
    evaluate_target_health = true
    name                   = aws_api_gateway_domain_name.shortener.regional_domain_name
    zone_id                = aws_api_gateway_domain_name.shortener.regional_zone_id
  }
}

# ==============================================================================
# DEPLOYMENT STAGE WITH X-RAY OBLIGATION
# ==============================================================================
resource "aws_api_gateway_deployment" "deploy" {
  rest_api_id = aws_api_gateway_rest_api.api.id

  depends_on = [
    aws_api_gateway_integration.post_integration,
    aws_api_gateway_integration.get_integration
  ]

  lifecycle {
    create_before_destroy = true
  }
}

resource "aws_api_gateway_stage" "prod" {
  deployment_id        = aws_api_gateway_deployment.deploy.id
  rest_api_id          = aws_api_gateway_rest_api.api.id
  stage_name           = "prod"
  xray_tracing_enabled = true
}

resource "aws_api_gateway_base_path_mapping" "shortener" {
  api_id      = aws_api_gateway_rest_api.api.id
  stage_name  = aws_api_gateway_stage.prod.stage_name
  domain_name = aws_api_gateway_domain_name.shortener.domain_name
}

# ==============================================================================
# LAMBDA PERMISSIONS: Authorization Handshake Policies
# ==============================================================================
resource "aws_lambda_permission" "apigw_create_permission" {
  statement_id  = "AllowExecutionFromAPIGateway"
  action        = "lambda:InvokeFunction"
  function_name = var.create_lambda_name
  principal     = "://amazonaws.com"
  source_arn    = "${aws_api_gateway_rest_api.api.execution_arn}/*/*"
}

resource "aws_lambda_permission" "apigw_retrieve_permission" {
  statement_id  = "AllowExecutionFromAPIGateway"
  action        = "lambda:InvokeFunction"
  function_name = var.retrieve_lambda_name
  principal     = "://amazonaws.com"
  source_arn    = "${aws_api_gateway_rest_api.api.execution_arn}/*/*"
}

# ==============================================================================
# STACK OUTPUTS
# ==============================================================================
output "api_gateway_stage_arn" {
  value = "${aws_api_gateway_rest_api.api.arn}/stages/${aws_api_gateway_stage.prod.stage_name}"
}
