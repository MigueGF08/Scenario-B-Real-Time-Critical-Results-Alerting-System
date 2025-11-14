# Cola SQS para resultados normales
# sqs.tf - Colas SQS para procesamiento de resultados normales

# Cola principal para resultados normales (no críticos)
resource "aws_sqs_queue" "normal_results" {
  name                       = "${local.name_prefix}-normal-results"
  visibility_timeout_seconds = var.sqs_visibility_timeout
  message_retention_seconds  = var.sqs_message_retention
  max_message_size           = 262144 # 256 KB
  delay_seconds              = 0
  receive_wait_time_seconds  = 20 # Long polling habilitado

  # Dead Letter Queue configurada
  redrive_policy = jsonencode({
    deadLetterTargetArn = aws_sqs_queue.normal_results_dlq.arn
    maxReceiveCount     = 3
  })

  # Encriptación en reposo
  kms_master_key_id                 = aws_kms_key.sqs_encryption.id
  kms_data_key_reuse_period_seconds = 300

  tags = merge(
    local.common_tags,
    {
      Name        = "${local.name_prefix}-normal-results"
      Description = "Cola para procesamiento batch de resultados normales"
    }
  )
}

# Dead Letter Queue para mensajes que fallaron
resource "aws_sqs_queue" "normal_results_dlq" {
  name                       = "${local.name_prefix}-normal-results-dlq"
  message_retention_seconds  = 1209600 # 14 días
  receive_wait_time_seconds  = 20

  kms_master_key_id                 = aws_kms_key.sqs_encryption.id
  kms_data_key_reuse_period_seconds = 300

  tags = merge(
    local.common_tags,
    {
      Name        = "${local.name_prefix}-normal-results-dlq"
      Description = "Dead Letter Queue para resultados normales"
    }
  )
}

# Cola FIFO para garantizar orden (opcional, para casos especiales)
resource "aws_sqs_queue" "ordered_results" {
  name                        = "${local.name_prefix}-ordered-results.fifo"
  fifo_queue                  = true
  content_based_deduplication = true
  deduplication_scope         = "messageGroup"
  fifo_throughput_limit       = "perMessageGroupId"
  visibility_timeout_seconds  = var.sqs_visibility_timeout
  message_retention_seconds   = var.sqs_message_retention

  # Dead Letter Queue
  redrive_policy = jsonencode({
    deadLetterTargetArn = aws_sqs_queue.ordered_results_dlq.arn
    maxReceiveCount     = 3
  })

  kms_master_key_id                 = aws_kms_key.sqs_encryption.id
  kms_data_key_reuse_period_seconds = 300

  tags = merge(
    local.common_tags,
    {
      Name        = "${local.name_prefix}-ordered-results-fifo"
      Description = "Cola FIFO para resultados que requieren orden"
    }
  )
}

resource "aws_sqs_queue" "ordered_results_dlq" {
  name                       = "${local.name_prefix}-ordered-results-dlq.fifo"
  fifo_queue                 = true
  message_retention_seconds  = 1209600

  kms_master_key_id                 = aws_kms_key.sqs_encryption.id
  kms_data_key_reuse_period_seconds = 300

  tags = merge(
    local.common_tags,
    {
      Name        = "${local.name_prefix}-ordered-results-dlq-fifo"
      Description = "Dead Letter Queue FIFO"
    }
  )
}

# KMS Key para encriptar mensajes SQS
resource "aws_kms_key" "sqs_encryption" {
  description             = "KMS key para encriptar mensajes SQS de CritAlert"
  deletion_window_in_days = 10
  enable_key_rotation     = true

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "Enable IAM User Permissions"
        Effect = "Allow"
        Principal = {
          AWS = "arn:aws:iam::${local.account_id}:root"
        }
        Action   = "kms:*"
        Resource = "*"
      },
      {
        Sid    = "Allow SQS to use the key"
        Effect = "Allow"
        Principal = {
          Service = "sqs.amazonaws.com"
        }
        Action = [
          "kms:Decrypt",
          "kms:GenerateDataKey"
        ]
        Resource = "*"
      }
    ]
  })

  tags = merge(
    local.common_tags,
    {
      Name = "${local.name_prefix}-sqs-encryption-key"
    }
  )
}

resource "aws_kms_alias" "sqs_encryption" {
  name          = "alias/${local.name_prefix}-sqs"
  target_key_id = aws_kms_key.sqs_encryption.key_id
}

# CloudWatch Alarms para monitorear las colas

# Alarm: Mensajes en DLQ
resource "aws_cloudwatch_metric_alarm" "dlq_messages" {
  alarm_name          = "${local.name_prefix}-sqs-dlq-messages"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = 1
  metric_name         = "ApproximateNumberOfMessagesVisible"
  namespace           = "AWS/SQS"
  period              = 300
  statistic           = "Average"
  threshold           = 0
  alarm_description   = "Alerta cuando hay mensajes en el DLQ de SQS"
  alarm_actions       = [aws_sns_topic.admin_alerts.arn]

  dimensions = {
    QueueName = aws_sqs_queue.normal_results_dlq.name
  }

  tags = local.common_tags
}

# Alarm: Cola muy larga (backlog)
resource "aws_cloudwatch_metric_alarm" "queue_depth" {
  alarm_name          = "${local.name_prefix}-sqs-high-depth"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = 2
  metric_name         = "ApproximateNumberOfMessagesVisible"
  namespace           = "AWS/SQS"
  period              = 300
  statistic           = "Average"
  threshold           = 1000
  alarm_description   = "Alerta cuando la cola tiene más de 1000 mensajes"
  alarm_actions       = [aws_sns_topic.admin_alerts.arn]

  dimensions = {
    QueueName = aws_sqs_queue.normal_results.name
  }

  tags = local.common_tags
}

# Alarm: Edad de mensajes muy alta
resource "aws_cloudwatch_metric_alarm" "message_age" {
  alarm_name          = "${local.name_prefix}-sqs-old-messages"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = 1
  metric_name         = "ApproximateAgeOfOldestMessage"
  namespace           = "AWS/SQS"
  period              = 300
  statistic           = "Maximum"
  threshold           = 600 # 10 minutos
  alarm_description   = "Alerta cuando hay mensajes con más de 10 minutos sin procesar"
  alarm_actions       = [aws_sns_topic.admin_alerts.arn]

  dimensions = {
    QueueName = aws_sqs_queue.normal_results.name
  }

  tags = local.common_tags
}

# Outputs
output "sqs_queues" {
  description = "URLs de las colas SQS"
  value = {
    normal_results     = aws_sqs_queue.normal_results.url
    normal_results_dlq = aws_sqs_queue.normal_results_dlq.url
    ordered_results    = aws_sqs_queue.ordered_results.url
  }
}

output "sqs_queue_arns" {
  description = "ARNs de las colas SQS"
  value = {
    normal_results     = aws_sqs_queue.normal_results.arn
    normal_results_dlq = aws_sqs_queue.normal_results_dlq.arn
    ordered_results    = aws_sqs_queue.ordered_results.arn
  }
}