# SNS topics y subscripciones
# sns.tf - SNS Topics y Subscripciones para Alertas

# Topic principal para alertas críticas
resource "aws_sns_topic" "critical_alerts" {
  name              = "${local.name_prefix}-critical-alerts"
  display_name      = "CritAlert Critical Lab Results"
  delivery_policy   = jsonencode({
    http = {
      defaultHealthyRetryPolicy = {
        minDelayTarget     = 1
        maxDelayTarget     = 5
        numRetries         = 3
        numMaxDelayRetries = 0
        numNoDelayRetries  = 0
        numMinDelayRetries = 0
        backoffFunction    = "linear"
      }
      disableSubscriptionOverrides = false
    }
  })

  # Encriptación en reposo
  kms_master_key_id = aws_kms_key.sns_encryption.id

  tags = merge(
    local.common_tags,
    {
      Name        = "${local.name_prefix}-critical-alerts"
      Description = "Topic SNS para alertas críticas de laboratorio"
    }
  )
}

# Topic para alertas escaladas (backup physicians)
resource "aws_sns_topic" "escalated_alerts" {
  name         = "${local.name_prefix}-escalated-alerts"
  display_name = "CritAlert Escalated Alerts"

  kms_master_key_id = aws_kms_key.sns_encryption.id

  tags = merge(
    local.common_tags,
    {
      Name        = "${local.name_prefix}-escalated-alerts"
      Description = "Topic SNS para alertas escaladas"
    }
  )
}

# Topic para alertas administrativas (último nivel de escalación)
resource "aws_sns_topic" "admin_alerts" {
  name         = "${local.name_prefix}-admin-alerts"
  display_name = "CritAlert Administrative Alerts"

  kms_master_key_id = aws_kms_key.sns_encryption.id

  tags = merge(
    local.common_tags,
    {
      Name        = "${local.name_prefix}-admin-alerts"
      Description = "Topic SNS para alertas administrativas"
    }
  )
}

# KMS Key para encriptar mensajes SNS
resource "aws_kms_key" "sns_encryption" {
  description             = "KMS key para encriptar mensajes SNS de CritAlert"
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
        Sid    = "Allow SNS to use the key"
        Effect = "Allow"
        Principal = {
          Service = "sns.amazonaws.com"
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
      Name = "${local.name_prefix}-sns-encryption-key"
    }
  )
}

resource "aws_kms_alias" "sns_encryption" {
  name          = "alias/${local.name_prefix}-sns"
  target_key_id = aws_kms_key.sns_encryption.key_id
}

# Subscripciones SMS para números de emergencia
resource "aws_sns_topic_subscription" "critical_alerts_sms" {
  count     = length(var.alert_phone_numbers)
  topic_arn = aws_sns_topic.critical_alerts.arn
  protocol  = "sms"
  endpoint  = var.alert_phone_numbers[count.index]
}

# Subscripciones Email para alertas críticas
resource "aws_sns_topic_subscription" "critical_alerts_email" {
  count     = length(var.alert_email_addresses)
  topic_arn = aws_sns_topic.critical_alerts.arn
  protocol  = "email"
  endpoint  = var.alert_email_addresses[count.index]
}

# Subscripción Email para administrador
resource "aws_sns_topic_subscription" "admin_alerts_email" {
  topic_arn = aws_sns_topic.admin_alerts.arn
  protocol  = "email"
  endpoint  = var.emergency_admin_email
}

# Topic para dead letter queue (mensajes que fallaron)
resource "aws_sns_topic" "alert_dlq" {
  name         = "${local.name_prefix}-alert-dlq"
  display_name = "CritAlert Failed Messages"

  kms_master_key_id = aws_kms_key.sns_encryption.id

  tags = merge(
    local.common_tags,
    {
      Name        = "${local.name_prefix}-alert-dlq"
      Description = "Dead Letter Queue para mensajes de alerta fallidos"
    }
  )
}

# Subscripción Email para DLQ (notificar cuando hay fallos)
resource "aws_sns_topic_subscription" "dlq_email" {
  topic_arn = aws_sns_topic.alert_dlq.arn
  protocol  = "email"
  endpoint  = var.emergency_admin_email
}

# CloudWatch Alarm: Mensajes en DLQ
resource "aws_cloudwatch_metric_alarm" "dlq_messages" {
  alarm_name          = "${local.name_prefix}-dlq-messages"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = 1
  metric_name         = "NumberOfMessagesSent"
  namespace           = "AWS/SNS"
  period              = 60
  statistic           = "Sum"
  threshold           = 0
  alarm_description   = "Alerta cuando hay mensajes en el DLQ"
  alarm_actions       = [aws_sns_topic.admin_alerts.arn]

  dimensions = {
    TopicName = aws_sns_topic.alert_dlq.name
  }

  tags = local.common_tags
}

# CloudWatch Alarm: Tasa de fallos en SNS
resource "aws_cloudwatch_metric_alarm" "sns_delivery_failures" {
  alarm_name          = "${local.name_prefix}-sns-delivery-failures"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = 2
  metric_name         = "NumberOfNotificationsFailed"
  namespace           = "AWS/SNS"
  period              = 300
  statistic           = "Sum"
  threshold           = 5
  alarm_description   = "Alerta cuando hay más de 5 fallos de entrega en SNS"
  alarm_actions       = [aws_sns_topic.admin_alerts.arn]

  dimensions = {
    TopicName = aws_sns_topic.critical_alerts.name
  }

  tags = local.common_tags
}

# Outputs
output "sns_topics" {
  description = "ARNs de los topics SNS"
  value = {
    critical_alerts  = aws_sns_topic.critical_alerts.arn
    escalated_alerts = aws_sns_topic.escalated_alerts.arn
    admin_alerts     = aws_sns_topic.admin_alerts.arn
    dlq              = aws_sns_topic.alert_dlq.arn
  }
}

output "sns_kms_key_id" {
  description = "ID de la KMS key para encriptación SNS"
  value       = aws_kms_key.sns_encryption.id
}