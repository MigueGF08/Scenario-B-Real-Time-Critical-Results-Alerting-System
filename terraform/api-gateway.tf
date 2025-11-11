# API Gateway
# api-gateway.tf - API Gateway REST para recibir resultados de laboratorio

# ============================================================================
# API GATEWAY REST API
# ============================================================================

resource "aws_api_gateway_rest_api" "critalert" {
  name        = "${local.name_prefix}-api"
  description = "API Gateway para CritAlert - Sistema de alertas críticas de laboratorio"

  endpoint_configuration {
    types = ["REGIONAL"]
  }

  tags = merge(
    local.common_tags,
    {
      Name = "${local.name_prefix}-api"
    }
  )
}

# ============================================================================
# RECURSOS Y MÉTODOS
# ============================================================================

# Recurso: /results
resource "aws_api_gateway_resource" "results" {
  rest_api_id = aws_api_gateway_rest_api.critalert.id
  parent_id   = aws_api_gateway_rest_api.critalert.root_resource_id
  path_part   = "results"
}

# Método: POST /results (para enviar resultados de laboratorio)
resource "aws_api_gateway_method" "post_results" {
  rest_api_id   = aws_api_gateway_rest_api.critalert.id
  resource_id   = aws_api_gateway_resource.results.id
  http_method   = "POST"
  authorization = "AWS_IAM" # Requerir autenticación IAM

  request_validator_id = aws_api_gateway_request_validator.body_validator.id

  # Modelo de validación del request
  request_models = {
    "application/json" = aws_api_gateway_model.lab_result.name
  }
}

# Integración: Lambda de Ingesta
resource "aws_api_gateway_integration" "post_results_lambda" {
  rest_api_id             = aws_api_gateway_rest_api.critalert.id
  resource_id             = aws_api_gateway_resource.results.id
  http_method             = aws_api_gateway_method.post_results.http_method
  integration_http_method = "POST"
  type                    = "AWS_PROXY"
  uri                     = aws_lambda_function.ingestion.invoke_arn
}

# Recurso: /alerts/{alertId}/acknowledge
resource "aws_api_gateway_resource" "alerts" {
  rest_api_id = aws_api_gateway_rest_api.critalert.id
  parent_id   = aws_api_gateway_rest_api.critalert.root_resource_id
  path_part   = "alerts"
}

resource "aws_api_gateway_resource" "alert_id" {
  rest_api_id = aws_api_gateway_rest_api.critalert.id
  parent_id   = aws_api_gateway_resource.alerts.id
  path_part   = "{alertId}"
}

resource "aws_api_gateway_resource" "acknowledge" {
  rest_api_id = aws_api_gateway_rest_api.critalert.id
  parent_id   = aws_api_gateway_resource.alert_id.id
  path_part   = "acknowledge"
}

# Método: POST /alerts/{alertId}/acknowledge
resource "aws_api_gateway_method" "acknowledge_alert" {
  rest_api_id   = aws_api_gateway_rest_api.critalert.id
  resource_id   = aws_api_gateway_resource.acknowledge.id
  http_method   = "POST"
  authorization = "AWS_IAM"

  request_parameters = {
    "method.request.path.alertId" = true
  }
}

# Integración: Lambda de Acknowledgment
resource "aws_api_gateway_integration" "acknowledge_lambda" {
  rest_api_id             = aws_api_gateway_rest_api.critalert.id
  resource_id             = aws_api_gateway_resource.acknowledge.id
  http_method             = aws_api_gateway_method.acknowledge_alert.http_method
  integration_http_method = "POST"
  type                    = "AWS_PROXY"
  uri                     = aws_lambda_function.acknowledgment.invoke_arn
}

# ============================================================================
# VALIDADORES Y MODELOS
# ============================================================================

# Validador de request body
resource "aws_api_gateway_request_validator" "body_validator" {
  name                        = "${local.name_prefix}-body-validator"
  rest_api_id                 = aws_api_gateway_rest_api.critalert.id
  validate_request_body       = true
  validate_request_parameters = true
}

# Modelo JSON para resultado de laboratorio
resource "aws_api_gateway_model" "lab_result" {
  rest_api_id  = aws_api_gateway_rest_api.critalert.id
  name         = "LabResult"
  description  = "Modelo para resultado de laboratorio"
  content_type = "application/json"

  schema = jsonencode({
    "$schema" = "http://json-schema.org/draft-04/schema#"
    title     = "Lab Result Schema"
    type      = "object"
    required  = ["patient_id", "test_code", "value", "unit", "ordering_physician"]
    properties = {
      result_id = {
        type = "string"
      }
      patient_id = {
        type = "string"
      }
      patient_name = {
        type = "string"
      }
      patient_age = {
        type = "integer"
        minimum = 0
      }
      test_code = {
        type = "string"
      }
      test_name = {
        type = "string"
      }
      value = {
        type = "number"
      }
      unit = {
        type = "string"
      }
      reference_range = {
        type = "string"
      }
      ordering_physician = {
        type = "object"
        required = ["physician_id", "name", "phone"]
        properties = {
          physician_id = {
            type = "string"
          }
          name = {
            type = "string"
          }
          npi = {
            type = "string"
          }
          phone = {
            type = "string"
          }
          pager = {
            type = "string"
          }
          email = {
            type = "string"
            format = "email"
          }
        }
      }
      backup_physician = {
        type = "object"
        properties = {
          physician_id = {
            type = "string"
          }
          name = {
            type = "string"
          }
          phone = {
            type = "string"
          }
        }
      }
      test_timestamp = {
        type = "string"
        format = "date-time"
      }
    }
  })
}

# ============================================================================
# PERMISOS PARA LAMBDA
# ============================================================================

# Permiso para API Gateway invocar Lambda de Ingesta
resource "aws_lambda_permission" "apigw_ingestion" {
  statement_id  = "AllowAPIGatewayInvoke"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.ingestion.function_name
  principal     = "apigateway.amazonaws.com"
  source_arn    = "${aws_api_gateway_rest_api.critalert.execution_arn}/*/*"
}

# Permiso para API Gateway invocar Lambda de Acknowledgment
resource "aws_lambda_permission" "apigw_acknowledgment" {
  statement_id  = "AllowAPIGatewayInvoke"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.acknowledgment.function_name
  principal     = "apigateway.amazonaws.com"
  source_arn    = "${aws_api_gateway_rest_api.critalert.execution_arn}/*/*"
}

# ============================================================================
# DEPLOYMENT Y STAGE
# ============================================================================

resource "aws_api_gateway_deployment" "critalert" {
  rest_api_id = aws_api_gateway_rest_api.critalert.id

  # Triggers para forzar re-deployment cuando cambian los recursos
  triggers = {
    redeployment = sha1(jsonencode([
      aws_api_gateway_resource.results.id,
      aws_api_gateway_method.post_results.id,
      aws_api_gateway_integration.post_results_lambda.id,
      aws_api_gateway_resource.acknowledge.id,
      aws_api_gateway_method.acknowledge_alert.id,
      aws_api_gateway_integration.acknowledge_lambda.id,
    ]))
  }

  lifecycle {
    create_before_destroy = true
  }

  depends_on = [
    aws_api_gateway_method.post_results,
    aws_api_gateway_integration.post_results_lambda,
    aws_api_gateway_method.acknowledge_alert,
    aws_api_gateway_integration.acknowledge_lambda,
  ]
}

resource "aws_api_gateway_stage" "critalert" {
  deployment_id = aws_api_gateway_deployment.critalert.id
  rest_api_id   = aws_api_gateway_rest_api.critalert.id
  stage_name    = var.environment

  # Access logs
  access_log_settings {
    destination_arn = aws_cloudwatch_log_group.api_gateway_logs.arn
    format = jsonencode({
      requestId      = "$context.requestId"
      ip             = "$context.identity.sourceIp"
      caller         = "$context.identity.caller"
      user           = "$context.identity.user"
      requestTime    = "$context.requestTime"
      httpMethod     = "$context.httpMethod"
      resourcePath   = "$context.resourcePath"
      status         = "$context.status"
      protocol       = "$context.protocol"
      responseLength = "$context.responseLength"
      errorMessage   = "$context.error.message"
    })
  }

  # X-Ray tracing
  xray_tracing_enabled = true

  tags = merge(
    local.common_tags,
    {
      Name = "${local.name_prefix}-api-${var.environment}"
    }
  )
}

# CloudWatch Log Group para API Gateway
resource "aws_cloudwatch_log_group" "api_gateway_logs" {
  name              = "/aws/apigateway/${local.name_prefix}"
  retention_in_days = var.log_retention_days

  tags = local.common_tags
}

# ============================================================================
# MÉTODO DE SETTINGS PARA TODA LA API
# ============================================================================

resource "aws_api_gateway_method_settings" "all" {
  rest_api_id = aws_api_gateway_rest_api.critalert.id
  stage_name  = aws_api_gateway_stage.critalert.stage_name
  method_path = "*/*"

  settings {
    metrics_enabled        = true
    logging_level          = "INFO"
    data_trace_enabled     = var.environment == "dev" ? true : false
    throttling_burst_limit = 500
    throttling_rate_limit  = 1000
  }
}

# ============================================================================
# CLOUDWATCH ALARMS
# ============================================================================

# Alarm: Alto número de errores 5XX
resource "aws_cloudwatch_metric_alarm" "api_5xx_errors" {
  alarm_name          = "${local.name_prefix}-api-5xx-errors"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = 2
  metric_name         = "5XXError"
  namespace           = "AWS/ApiGateway"
  period              = 300
  statistic           = "Sum"
  threshold           = 10
  alarm_description   = "Alerta cuando hay más de 10 errores 5XX en 5 minutos"
  alarm_actions       = [aws_sns_topic.admin_alerts.arn]

  dimensions = {
    ApiName = aws_api_gateway_rest_api.critalert.name
    Stage   = aws_api_gateway_stage.critalert.stage_name
  }

  tags = local.common_tags
}

# Alarm: Latencia alta
resource "aws_cloudwatch_metric_alarm" "api_latency" {
  alarm_name          = "${local.name_prefix}-api-high-latency"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = 2
  metric_name         = "Latency"
  namespace           = "AWS/ApiGateway"
  period              = 300
  statistic           = "Average"
  threshold           = 5000 # 5 segundos
  alarm_description   = "Alerta cuando la latencia promedio supera 5 segundos"
  alarm_actions       = [aws_sns_topic.admin_alerts.arn]

  dimensions = {
    ApiName = aws_api_gateway_rest_api.critalert.name
    Stage   = aws_api_gateway_stage.critalert.stage_name
  }

  tags = local.common_tags
}

# ============================================================================
# OUTPUTS
# ============================================================================

output "api_gateway_info" {
  description = "Información del API Gateway"
  value = {
    id           = aws_api_gateway_rest_api.critalert.id
    name         = aws_api_gateway_rest_api.critalert.name
    endpoint_url = aws_api_gateway_stage.critalert.invoke_url
    stage        = aws_api_gateway_stage.critalert.stage_name
  }
}

output "api_endpoints" {
  description = "Endpoints del API"
  value = {
    submit_result     = "${aws_api_gateway_stage.critalert.invoke_url}/results"
    acknowledge_alert = "${aws_api_gateway_stage.critalert.invoke_url}/alerts/{alertId}/acknowledge"
  }
}