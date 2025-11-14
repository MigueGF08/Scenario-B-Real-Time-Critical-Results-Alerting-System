# Dashboards y alarmas
# cloudwatch.tf - Dashboard y métricas personalizadas

# ============================================================================
# CLOUDWATCH DASHBOARD
# ============================================================================

resource "aws_cloudwatch_dashboard" "critalert" {
  dashboard_name = "${local.name_prefix}-dashboard"

  dashboard_body = jsonencode({
    widgets = [
      # Widget 1: Alertas Críticas por Hora
      {
        type = "metric"
        properties = {
          metrics = [
            ["CritAlert", "CriticalAlertsTriggered", { stat = "Sum", label = "Alertas Críticas" }],
            [".", "CriticalAlertsAcknowledged", { stat = "Sum", label = "Confirmadas" }],
            [".", "CriticalAlertsEscalated", { stat = "Sum", label = "Escaladas" }]
          ]
          period = 300
          stat   = "Sum"
          region = local.region
          title  = "Alertas Críticas - Última Hora"
          yAxis = {
            left = {
              min = 0
            }
          }
        }
      },

      # Widget 2: Latencia de Alertas
      {
        type = "metric"
        properties = {
          metrics = [
            ["CritAlert", "AlertLatencySeconds", { stat = "Average", label = "Latencia Promedio" }],
            ["...", { stat = "Maximum", label = "Latencia Máxima" }],
            [{
              expression = "m1"
              label      = "SLA (60s)"
              color      = "#d13212"
            }]
          ]
          period = 300
          stat   = "Average"
          region = local.region
          title  = "Latencia de Alertas (SLA: 60 segundos)"
          annotations = {
            horizontal = [
              {
                value = 60
                label = "SLA Límite"
                fill  = "above"
                color = "#ff0000"
              }
            ]
          }
          yAxis = {
            left = {
              min = 0
              max = 120
            }
          }
        }
      },

      # Widget 3: API Gateway - Requests y Errores
      {
        type = "metric"
        properties = {
          metrics = [
            ["AWS/ApiGateway", "Count", { stat = "Sum", label = "Total Requests" }],
            [".", "4XXError", { stat = "Sum", label = "Errores 4XX" }],
            [".", "5XXError", { stat = "Sum", label = "Errores 5XX" }]
          ]
          period = 300
          stat   = "Sum"
          region = local.region
          title  = "API Gateway - Tráfico y Errores"
        }
      },

      # Widget 4: Lambda Invocations
      {
        type = "metric"
        properties = {
          metrics = [
            ["AWS/Lambda", "Invocations", { stat = "Sum", dimensions = { FunctionName = "${local.name_prefix}-ingestion" }, label = "Ingesta" }],
            ["...", { dimensions = { FunctionName = "${local.name_prefix}-critical-alert-handler" }, label = "Alert Handler" }],
            ["...", { dimensions = { FunctionName = "${local.name_prefix}-normal-processor" }, label = "Normal Processor" }]
          ]
          period = 300
          stat   = "Sum"
          region = local.region
          title  = "Lambda - Invocaciones por Función"
        }
      },

      # Widget 5: Lambda Errors
      {
        type = "metric"
        properties = {
          metrics = [
            ["AWS/Lambda", "Errors", { stat = "Sum", dimensions = { FunctionName = "${local.name_prefix}-ingestion" }, label = "Ingesta" }],
            ["...", { dimensions = { FunctionName = "${local.name_prefix}-critical-alert-handler" }, label = "Alert Handler" }],
            ["...", { dimensions = { FunctionName = "${local.name_prefix}-normal-processor" }, label = "Normal Processor" }]
          ]
          period = 300
          stat   = "Sum"
          region = local.region
          title  = "Lambda - Errores"
          yAxis = {
            left = {
              min = 0
            }
          }
        }
      },

      # Widget 6: SQS - Profundidad de Cola
      {
        type = "metric"
        properties = {
          metrics = [
            ["AWS/SQS", "ApproximateNumberOfMessagesVisible", { stat = "Average", dimensions = { QueueName = "${local.name_prefix}-normal-results" }, label = "Mensajes Visibles" }],
            [".", "ApproximateAgeOfOldestMessage", { stat = "Maximum", yAxis = "right", label = "Edad Mensaje Más Viejo (seg)" }]
          ]
          period = 300
          stat   = "Average"
          region = local.region
          title  = "SQS - Estado de Cola Normal"
        }
      },

      # Widget 7: Step Functions - Ejecuciones
      {
        type = "metric"
        properties = {
          metrics = [
            ["AWS/States", "ExecutionsStarted", { stat = "Sum", label = "Iniciadas" }],
            [".", "ExecutionsSucceeded", { stat = "Sum", label = "Exitosas" }],
            [".", "ExecutionsFailed", { stat = "Sum", label = "Fallidas" }],
            [".", "ExecutionsTimedOut", { stat = "Sum", label = "Timeout" }]
          ]
          period = 300
          stat   = "Sum"
          region = local.region
          title  = "Step Functions - Ejecuciones de Escalación"
        }
      },

      # Widget 8: DynamoDB - Operaciones
      {
        type = "metric"
        properties = {
          metrics = [
            ["AWS/DynamoDB", "ConsumedReadCapacityUnits", { stat = "Sum", dimensions = { TableName = "${local.name_prefix}-alerts" }, label = "Lecturas" }],
            [".", "ConsumedWriteCapacityUnits", { stat = "Sum", dimensions = { TableName = "${local.name_prefix}-alerts" }, label = "Escrituras" }]
          ]
          period = 300
          stat   = "Sum"
          region = local.region
          title  = "DynamoDB - Capacidad Consumida (Tabla Alerts)"
        }
      },

      # Widget 9: SNS - Notificaciones Enviadas
      {
        type = "metric"
        properties = {
          metrics = [
            ["AWS/SNS", "NumberOfMessagesPublished", { stat = "Sum", dimensions = { TopicName = "${local.name_prefix}-critical-alerts" }, label = "Críticas" }],
            ["...", { dimensions = { TopicName = "${local.name_prefix}-escalated-alerts" }, label = "Escaladas" }],
            [".", "NumberOfNotificationsFailed", { stat = "Sum", yAxis = "right", label = "Fallidas" }]
          ]
          period = 300
          stat   = "Sum"
          region = local.region
          title  = "SNS - Notificaciones Enviadas"
        }
      },

      # Widget 10: Métricas de SLA
      {
        type = "metric"
        properties = {
          metrics = [
            ["CritAlert", "SLACompliance", { stat = "Average", label = "% Cumplimiento SLA" }]
          ]
          period = 3600
          stat   = "Average"
          region = local.region
          title  = "Cumplimiento de SLA (< 60 segundos)"
          annotations = {
            horizontal = [
              {
                value = 95
                label = "Target 95%"
                fill  = "below"
                color = "#ff7f0e"
              }
            ]
          }
          yAxis = {
            left = {
              min = 0
              max = 100
            }
          }
        }
      }
    ]
  })
}

# ============================================================================
# MÉTRICAS PERSONALIZADAS
# ============================================================================

# Log Metric Filter: Detectar alertas críticas enviadas
resource "aws_cloudwatch_log_metric_filter" "critical_alerts_triggered" {
  name           = "${local.name_prefix}-critical-alerts-triggered"
  log_group_name = aws_cloudwatch_log_group.lambda_alert_handler.name
  pattern        = "[time, request_id, level = \"INFO\", msg = \"CRITICAL_ALERT_TRIGGERED\", ...]"

  metric_transformation {
    name      = "CriticalAlertsTriggered"
    namespace = "CritAlert"
    value     = "1"
    unit      = "Count"
  }
}

# Log Metric Filter: Detectar alertas confirmadas
resource "aws_cloudwatch_log_metric_filter" "critical_alerts_acknowledged" {
  name           = "${local.name_prefix}-critical-alerts-acknowledged"
  log_group_name = aws_cloudwatch_log_group.lambda_acknowledgment.name
  pattern        = "[time, request_id, level = \"INFO\", msg = \"ALERT_ACKNOWLEDGED\", ...]"

  metric_transformation {
    name      = "CriticalAlertsAcknowledged"
    namespace = "CritAlert"
    value     = "1"
    unit      = "Count"
  }
}

# Log Metric Filter: Detectar alertas escaladas
resource "aws_cloudwatch_log_metric_filter" "critical_alerts_escalated" {
  name           = "${local.name_prefix}-critical-alerts-escalated"
  log_group_name = aws_cloudwatch_log_group.lambda_escalation.name
  pattern        = "[time, request_id, level = \"INFO\", msg = \"ALERT_ESCALATED\", ...]"

  metric_transformation {
    name      = "CriticalAlertsEscalated"
    namespace = "CritAlert"
    value     = "1"
    unit      = "Count"
  }
}

# Log Metric Filter: Medir latencia de alertas
resource "aws_cloudwatch_log_metric_filter" "alert_latency" {
  name           = "${local.name_prefix}-alert-latency"
  log_group_name = aws_cloudwatch_log_group.lambda_alert_handler.name
  pattern        = "[time, request_id, level = \"INFO\", msg = \"ALERT_SENT\", latency_ms = *latency_ms*]"

  metric_transformation {
    name      = "AlertLatencySeconds"
    namespace = "CritAlert"
    value     = "$latency_ms/1000"
    unit      = "Seconds"
  }
}

# Log Metric Filter: SLA Compliance (alertas enviadas en < 60 segundos)
resource "aws_cloudwatch_log_metric_filter" "sla_compliance" {
  name           = "${local.name_prefix}-sla-compliance"
  log_group_name = aws_cloudwatch_log_group.lambda_alert_handler.name
  pattern        = "[time, request_id, level = \"INFO\", msg = \"SLA_CHECK\", met_sla = *met_sla*]"

  metric_transformation {
    name      = "SLACompliance"
    namespace = "CritAlert"
    value     = "$met_sla"
    unit      = "Percent"
  }
}

# ============================================================================
# ALARMS ADICIONALES
# ============================================================================

# Alarm: SLA Compliance bajo
resource "aws_cloudwatch_metric_alarm" "sla_compliance_low" {
  alarm_name          = "${local.name_prefix}-sla-compliance-low"
  comparison_operator = "LessThanThreshold"
  evaluation_periods  = 2
  metric_name         = "SLACompliance"
  namespace           = "CritAlert"
  period              = 3600
  statistic           = "Average"
  threshold           = 95 # 95% de cumplimiento
  alarm_description   = "Alerta cuando el cumplimiento de SLA cae por debajo del 95%"
  alarm_actions       = [aws_sns_topic.admin_alerts.arn]

  treat_missing_data = "notBreaching"

  tags = local.common_tags
}

# Alarm: Alto número de escalaciones
resource "aws_cloudwatch_metric_alarm" "high_escalations" {
  alarm_name          = "${local.name_prefix}-high-escalations"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = 2
  metric_name         = "CriticalAlertsEscalated"
  namespace           = "CritAlert"
  period              = 3600
  statistic           = "Sum"
  threshold           = 10
  alarm_description   = "Alerta cuando hay más de 10 escalaciones en una hora"
  alarm_actions       = [aws_sns_topic.admin_alerts.arn]

  treat_missing_data = "notBreaching"

  tags = local.common_tags
}

# Alarm: Muchas alertas críticas (posible problema sistémico)
resource "aws_cloudwatch_metric_alarm" "high_critical_alerts" {
  alarm_name          = "${local.name_prefix}-high-critical-alerts"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = 1
  metric_name         = "CriticalAlertsTriggered"
  namespace           = "CritAlert"
  period              = 3600
  statistic           = "Sum"
  threshold           = 50
  alarm_description   = "Alerta cuando hay más de 50 alertas críticas en una hora (posible problema sistémico)"
  alarm_actions       = [aws_sns_topic.admin_alerts.arn]

  treat_missing_data = "notBreaching"

  tags = local.common_tags
}

# ============================================================================
# CLOUDWATCH INSIGHTS QUERIES (guardadas)
# ============================================================================

resource "aws_cloudwatch_query_definition" "failed_alerts" {
  name = "${local.name_prefix}-failed-alerts"

  log_group_names = [
    aws_cloudwatch_log_group.lambda_alert_handler.name
  ]

  query_string = <<-QUERY
    fields @timestamp, @message
    | filter @message like /ERROR/
    | filter @message like /ALERT_FAILED/
    | sort @timestamp desc
    | limit 100
  QUERY
}

resource "aws_cloudwatch_query_definition" "alert_latency_analysis" {
  name = "${local.name_prefix}-alert-latency-analysis"

  log_group_names = [
    aws_cloudwatch_log_group.lambda_alert_handler.name
  ]

  query_string = <<-QUERY
    fields @timestamp, latency_ms
    | filter @message like /ALERT_SENT/
    | stats avg(latency_ms) as avg_latency, max(latency_ms) as max_latency, min(latency_ms) as min_latency, count() as total_alerts by bin(5m)
    | sort @timestamp desc
  QUERY
}

resource "aws_cloudwatch_query_definition" "unacknowledged_alerts" {
  name = "${local.name_prefix}-unacknowledged-alerts"

  log_group_names = [
    aws_cloudwatch_log_group.lambda_escalation.name
  ]

  query_string = <<-QUERY
    fields @timestamp, alert_id, patient_name, escalation_level
    | filter @message like /ALERT_ESCALATED/
    | sort @timestamp desc
    | limit 50
  QUERY
}

# ============================================================================
# OUTPUTS
# ============================================================================

output "cloudwatch_dashboard_url" {
  description = "URL del Dashboard de CloudWatch"
  value       = "https://console.aws.amazon.com/cloudwatch/home?region=${local.region}#dashboards:name=${aws_cloudwatch_dashboard.critalert.dashboard_name}"
}

output "cloudwatch_alarms" {
  description = "Lista de alarmas de CloudWatch creadas"
  value = {
    sla_compliance    = aws_cloudwatch_metric_alarm.sla_compliance_low.alarm_name
    high_escalations  = aws_cloudwatch_metric_alarm.high_escalations.alarm_name
    high_critical_alerts = aws_cloudwatch_metric_alarm.high_critical_alerts.alarm_name
  }
}