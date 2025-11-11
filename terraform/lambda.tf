# Funciones Lambda
# lambda.tf - Definición de funciones Lambda

# ============================================================================
# LAMBDA 1: Ingesta de Resultados (Router)
# ============================================================================

# Archivo ZIP con el código Lambda
data "archive_file" "lambda_ingestion" {
  type        = "zip"
  source_dir  = "${path.module}/../lambda/ingestion"
  output_path = "${path.module}/.terraform/lambda_ingestion.zip"
}

resource "aws_lambda_function" "ingestion" {
  filename         = data.archive_file.lambda_ingestion.output_path
  function_name    = "${local.name_prefix}-ingestion"
  role             = aws_iam_role.lambda_ingestion.arn
  handler          = "index.handler"
  source_code_hash = data.archive_file.lambda_ingestion.output_base64sha256
  runtime          = var.lambda_runtime
  timeout          = var.lambda_timeout
  memory_size      = var.lambda_memory_size

  environment {
    variables = {
      ENVIRONMENT              = var.environment
      THRESHOLDS_TABLE         = aws_dynamodb_table.critical_thresholds.name
      LAB_RESULTS_TABLE        = aws_dynamodb_table.lab_results.name
      NORMAL_RESULTS_QUEUE     = aws_sqs_queue.normal_results.url
      CRITICAL_ALERT_FUNCTION  = "${local.name_prefix}-critical-alert-handler"
      ALERT_SLA_SECONDS        = var.alert_sla_seconds
      AWS_REGION_NAME          = local.region
    }
  }

  # Reserved concurrent executions para garantizar disponibilidad
  reserved_concurrent_executions = 10

  # Tracing con X-Ray
  tracing_config {
    mode = "Active"
  }

  # Dead letter config
  dead_letter_config {
    target_arn = aws_sns_topic.alert_dlq.arn
  }

  tags = merge(
    local.common_tags,
    {
      Name        = "${local.name_prefix}-ingestion"
      Description = "Lambda para ingesta y routing de resultados de laboratorio"
    }
  )
}

# CloudWatch Log Group para Lambda Ingestion
resource "aws_cloudwatch_log_group" "lambda_ingestion" {
  name              = "/aws/lambda/${aws_lambda_function.ingestion.function_name}"
  retention_in_days = var.log_retention_days

  tags = local.common_tags
}

# ============================================================================
# LAMBDA 2: Manejo de Alertas Críticas
# ============================================================================

data "archive_file" "lambda_alert_handler" {
  type        = "zip"
  source_dir  = "${path.module}/../lambda/alert-handler"
  output_path = "${path.module}/.terraform/lambda_alert_handler.zip"
}

resource "aws_lambda_function" "alert_handler" {
  filename         = data.archive_file.lambda_alert_handler.output_path
  function_name    = "${local.name_prefix}-critical-alert-handler"
  role             = aws_iam_role.lambda_alert_handler.arn
  handler          = "index.handler"
  source_code_hash = data.archive_file.lambda_alert_handler.output_base64sha256
  runtime          = var.lambda_runtime
  timeout          = 60 # Más tiempo para manejar alertas
  memory_size      = 512 # Más memoria para procesamiento complejo

  environment {
    variables = {
      ENVIRONMENT             = var.environment
      ALERTS_TABLE            = aws_dynamodb_table.alerts.name
      PHYSICIANS_TABLE        = aws_dynamodb_table.physicians.name
      ESCALATION_CONFIG_TABLE = aws_dynamodb_table.escalation_config.name
      SNS_CRITICAL_TOPIC      = aws_sns_topic.critical_alerts.arn
      SNS_ESCALATED_TOPIC     = aws_sns_topic.escalated_alerts.arn
      SNS_ADMIN_TOPIC         = aws_sns_topic.admin_alerts.arn
      ESCALATION_STATE_MACHINE = "arn:aws:states:${local.region}:${local.account_id}:stateMachine:${local.name_prefix}-escalation-workflow"
      AWS_REGION_NAME         = local.region
    }
  }

  reserved_concurrent_executions = 20

  tracing_config {
    mode = "Active"
  }

  dead_letter_config {
    target_arn = aws_sns_topic.alert_dlq.arn
  }

  tags = merge(
    local.common_tags,
    {
      Name        = "${local.name_prefix}-critical-alert-handler"
      Description = "Lambda para manejo de alertas críticas"
    }
  )
}

resource "aws_cloudwatch_log_group" "lambda_alert_handler" {
  name              = "/aws/lambda/${aws_lambda_function.alert_handler.function_name}"
  retention_in_days = var.log_retention_days

  tags = local.common_tags
}

# ============================================================================
# LAMBDA 3: Procesamiento Normal (SQS Consumer)
# ============================================================================

data "archive_file" "lambda_normal_processor" {
  type        = "zip"
  source_dir  = "${path.module}/../lambda/normal-processor"
  output_path = "${path.module}/.terraform/lambda_normal_processor.zip"
}

resource "aws_lambda_function" "normal_processor" {
  filename         = data.archive_file.lambda_normal_processor.output_path
  function_name    = "${local.name_prefix}-normal-processor"
  role             = aws_iam_role.lambda_normal_processor.arn
  handler          = "index.handler"
  source_code_hash = data.archive_file.lambda_normal_processor.output_base64sha256
  runtime          = var.lambda_runtime
  timeout          = var.lambda_timeout
  memory_size      = var.lambda_memory_size

  environment {
    variables = {
      ENVIRONMENT       = var.environment
      LAB_RESULTS_TABLE = aws_dynamodb_table.lab_results.name
      AWS_REGION_NAME   = local.region
    }
  }

  tracing_config {
    mode = "Active"
  }

  tags = merge(
    local.common_tags,
    {
      Name        = "${local.name_prefix}-normal-processor"
      Description = "Lambda para procesamiento batch de resultados normales"
    }
  )
}

resource "aws_cloudwatch_log_group" "lambda_normal_processor" {
  name              = "/aws/lambda/${aws_lambda_function.normal_processor.function_name}"
  retention_in_days = var.log_retention_days

  tags = local.common_tags
}

# Event Source Mapping: SQS -> Lambda
resource "aws_lambda_event_source_mapping" "sqs_normal_processor" {
  event_source_arn = aws_sqs_queue.normal_results.arn
  function_name    = aws_lambda_function.normal_processor.arn
  batch_size       = 10
  enabled          = true

  # Configuración de reintentos
  scaling_config {
    maximum_concurrency = 5
  }

  function_response_types = ["ReportBatchItemFailures"]
}

# ============================================================================
# LAMBDA 4: Confirmación de Alertas (Acknowledgment)
# ============================================================================

data "archive_file" "lambda_acknowledgment" {
  type        = "zip"
  source_dir  = "${path.module}/../lambda/acknowledgment"
  output_path = "${path.module}/.terraform/lambda_acknowledgment.zip"
}

resource "aws_lambda_function" "acknowledgment" {
  filename         = data.archive_file.lambda_acknowledgment.output_path
  function_name    = "${local.name_prefix}-acknowledgment"
  role             = aws_iam_role.lambda_acknowledgment.arn
  handler          = "index.handler"
  source_code_hash = data.archive_file.lambda_acknowledgment.output_base64sha256
  runtime          = var.lambda_runtime
  timeout          = var.lambda_timeout
  memory_size      = var.lambda_memory_size

  environment {
    variables = {
      ENVIRONMENT              = var.environment
      ALERTS_TABLE             = aws_dynamodb_table.alerts.name
      ESCALATION_STATE_MACHINE = "arn:aws:states:${local.region}:${local.account_id}:stateMachine:${local.name_prefix}-escalation-workflow"
      AWS_REGION_NAME          = local.region
    }
  }

  tracing_config {
    mode = "Active"
  }

  tags = merge(
    local.common_tags,
    {
      Name        = "${local.name_prefix}-acknowledgment"
      Description = "Lambda para procesar confirmaciones de alertas"
    }
  )
}

resource "aws_cloudwatch_log_group" "lambda_acknowledgment" {
  name              = "/aws/lambda/${aws_lambda_function.acknowledgment.function_name}"
  retention_in_days = var.log_retention_days

  tags = local.common_tags
}

# ============================================================================
# LAMBDA 5: Escalación (usado por Step Functions)
# ============================================================================

data "archive_file" "lambda_escalation" {
  type        = "zip"
  source_dir  = "${path.module}/../lambda/escalation"
  output_path = "${path.module}/.terraform/lambda_escalation.zip"
}

resource "aws_lambda_function" "escalation" {
  filename         = data.archive_file.lambda_escalation.output_path
  function_name    = "${local.name_prefix}-escalation-handler"
  role             = aws_iam_role.lambda_alert_handler.arn
  handler          = "index.handler"
  source_code_hash = data.archive_file.lambda_escalation.output_base64sha256
  runtime          = var.lambda_runtime
  timeout          = 60
  memory_size      = 512

  environment {
    variables = {
      ENVIRONMENT         = var.environment
      ALERTS_TABLE        = aws_dynamodb_table.alerts.name
      PHYSICIANS_TABLE    = aws_dynamodb_table.physicians.name
      SNS_ESCALATED_TOPIC = aws_sns_topic.escalated_alerts.arn
      SNS_ADMIN_TOPIC     = aws_sns_topic.admin_alerts.arn
      AWS_REGION_NAME     = local.region
    }
  }

  tracing_config {
    mode = "Active"
  }

  tags = merge(
    local.common_tags,
    {
      Name        = "${local.name_prefix}-escalation-handler"
      Description = "Lambda para manejo de escalación de alertas"
    }
  )
}

resource "aws_cloudwatch_log_group" "lambda_escalation" {
  name              = "/aws/lambda/${aws_lambda_function.escalation.function_name}"
  retention_in_days = var.log_retention_days

  tags = local.common_tags
}

# ============================================================================
# CLOUDWATCH ALARMS PARA LAMBDAS
# ============================================================================

# Alarm: Errores en Lambda de Ingesta
resource "aws_cloudwatch_metric_alarm" "lambda_ingestion_errors" {
  alarm_name          = "${local.name_prefix}-lambda-ingestion-errors"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = 2
  metric_name         = "Errors"
  namespace           = "AWS/Lambda"
  period              = 300
  statistic           = "Sum"
  threshold           = 5
  alarm_description   = "Alerta cuando hay más de 5 errores en Lambda de ingesta"
  alarm_actions       = [aws_sns_topic.admin_alerts.arn]

  dimensions = {
    FunctionName = aws_lambda_function.ingestion.function_name
  }

  tags = local.common_tags
}

# Alarm: Duración alta en Lambda de Alertas
resource "aws_cloudwatch_metric_alarm" "lambda_alert_duration" {
  alarm_name          = "${local.name_prefix}-lambda-alert-high-duration"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = 2
  metric_name         = "Duration"
  namespace           = "AWS/Lambda"
  period              = 300
  statistic           = "Average"
  threshold           = 55000 # 55 segundos (cerca del timeout de 60)
  alarm_description   = "Alerta cuando la duración promedio se acerca al timeout"
  alarm_actions       = [aws_sns_topic.admin_alerts.arn]

  dimensions = {
    FunctionName = aws_lambda_function.alert_handler.function_name
  }

  tags = local.common_tags
}

# Alarm: Throttling en Lambda Crítica
resource "aws_cloudwatch_metric_alarm" "lambda_alert_throttles" {
  alarm_name          = "${local.name_prefix}-lambda-alert-throttles"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = 1
  metric_name         = "Throttles"
  namespace           = "AWS/Lambda"
  period              = 60
  statistic           = "Sum"
  threshold           = 0
  alarm_description   = "Alerta cuando Lambda de alertas es throttled"
  alarm_actions       = [aws_sns_topic.admin_alerts.arn]

  dimensions = {
    FunctionName = aws_lambda_function.alert_handler.function_name
  }

  tags = local.common_tags
}

# ============================================================================
# OUTPUTS
# ============================================================================

output "lambda_functions" {
  description = "ARNs de las funciones Lambda"
  value = {
    ingestion        = aws_lambda_function.ingestion.arn
    alert_handler    = aws_lambda_function.alert_handler.arn
    normal_processor = aws_lambda_function.normal_processor.arn
    acknowledgment   = aws_lambda_function.acknowledgment.arn
    escalation       = aws_lambda_function.escalation.arn
  }
}

output "lambda_function_names" {
  description = "Nombres de las funciones Lambda"
  value = {
    ingestion        = aws_lambda_function.ingestion.function_name
    alert_handler    = aws_lambda_function.alert_handler.function_name
    normal_processor = aws_lambda_function.normal_processor.function_name
    acknowledgment   = aws_lambda_function.acknowledgment.function_name
    escalation       = aws_lambda_function.escalation.function_name
  }
}