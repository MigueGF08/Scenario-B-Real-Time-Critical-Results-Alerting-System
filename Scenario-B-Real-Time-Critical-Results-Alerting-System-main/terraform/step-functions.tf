# State machine de escalación
# step-functions.tf - State Machine para escalación automática de alertas

# ============================================================================
# STEP FUNCTIONS STATE MACHINE
# ============================================================================

resource "aws_sfn_state_machine" "escalation_workflow" {
  name     = "${local.name_prefix}-escalation-workflow"
  role_arn = aws_iam_role.step_functions.arn

  definition = jsonencode({
    Comment = "Workflow de escalación automática para alertas críticas no confirmadas"
    StartAt = "SendPrimaryAlert"
    States = {
      # Estado 1: Enviar alerta al médico principal
      SendPrimaryAlert = {
        Type     = "Task"
        Resource = "arn:aws:states:::sns:publish"
        Parameters = {
          TopicArn = aws_sns_topic.critical_alerts.arn
          Message = {
            "alert_id.$"        = "$.alert_id"
            "patient_name.$"    = "$.patient_name"
            "test_name.$"       = "$.test_name"
            "value.$"           = "$.value"
            "criticality.$"     = "$.criticality"
            "physician_name.$"  = "$.ordering_physician.name"
            "physician_phone.$" = "$.ordering_physician.phone"
            escalation_level    = "PRIMARY"
            message_type        = "CRITICAL_ALERT"
          }
          MessageAttributes = {
            alert_id = {
              DataType    = "String"
              "StringValue.$" = "$.alert_id"
            }
            urgency = {
              DataType    = "String"
              StringValue = "CRITICAL"
            }
          }
        }
        ResultPath = "$.primary_alert_result"
        Next       = "UpdateAlertStatusPrimary"
        Retry = [
          {
            ErrorEquals     = ["States.TaskFailed"]
            IntervalSeconds = 2
            MaxAttempts     = 3
            BackoffRate     = 2.0
          }
        ]
        Catch = [
          {
            ErrorEquals = ["States.ALL"]
            ResultPath  = "$.error_info"
            Next        = "AlertFailureNotification"
          }
        ]
      }

      # Actualizar estado en DynamoDB
      UpdateAlertStatusPrimary = {
        Type     = "Task"
        Resource = "arn:aws:states:::dynamodb:updateItem"
        Parameters = {
          TableName = aws_dynamodb_table.alerts.name
          Key = {
            alert_id = {
              "S.$" = "$.alert_id"
            }
            timestamp = {
              "N.$" = "$.timestamp"
            }
          }
          UpdateExpression = "SET #status = :status, primary_alert_sent = :sent_time"
          ExpressionAttributeNames = {
            "#status" = "status"
          }
          ExpressionAttributeValues = {
            ":status" = {
              S = "PRIMARY_SENT"
            }
            ":sent_time" = {
              "N.$" = "$$.State.EnteredTime"
            }
          }
        }
        ResultPath = null
        Next       = "WaitPrimaryResponse"
      }

      # Esperar respuesta del médico principal (5 minutos)
      WaitPrimaryResponse = {
        Type    = "Wait"
        Seconds = 300 # 5 minutos (usar variable)
        Next    = "CheckPrimaryAcknowledgment"
      }

      # Verificar si el médico principal confirmó
      CheckPrimaryAcknowledgment = {
        Type     = "Task"
        Resource = aws_lambda_function.escalation.arn
        Parameters = {
          "alert_id.$"       = "$.alert_id"
          action             = "check_acknowledgment"
          escalation_level   = "PRIMARY"
        }
        ResultPath = "$.acknowledgment_check"
        Next       = "IsPrimaryAcknowledged"
        Retry = [
          {
            ErrorEquals     = ["States.TaskFailed"]
            IntervalSeconds = 2
            MaxAttempts     = 3
            BackoffRate     = 2.0
          }
        ]
      }

      # Decisión: ¿Fue confirmado?
      IsPrimaryAcknowledged = {
        Type = "Choice"
        Choices = [
          {
            Variable      = "$.acknowledgment_check.acknowledged"
            BooleanEquals = true
            Next          = "AlertAcknowledgedSuccess"
          }
        ]
        Default = "EscalateToBackup"
      }

      # Estado 2: Escalar a médico de respaldo
      EscalateToBackup = {
        Type     = "Task"
        Resource = aws_lambda_function.escalation.arn
        Parameters = {
          "alert_id.$"           = "$.alert_id"
          "patient_name.$"       = "$.patient_name"
          "test_name.$"          = "$.test_name"
          "value.$"              = "$.value"
          "criticality.$"        = "$.criticality"
          "backup_physician.$"   = "$.backup_physician"
          action                 = "escalate"
          escalation_level       = "BACKUP"
          "previous_physician.$" = "$.ordering_physician.name"
        }
        ResultPath = "$.backup_alert_result"
        Next       = "UpdateAlertStatusBackup"
        Retry = [
          {
            ErrorEquals     = ["States.TaskFailed"]
            IntervalSeconds = 2
            MaxAttempts     = 3
            BackoffRate     = 2.0
          }
        ]
      }

      UpdateAlertStatusBackup = {
        Type     = "Task"
        Resource = "arn:aws:states:::dynamodb:updateItem"
        Parameters = {
          TableName = aws_dynamodb_table.alerts.name
          Key = {
            alert_id = {
              "S.$" = "$.alert_id"
            }
            timestamp = {
              "N.$" = "$.timestamp"
            }
          }
          UpdateExpression = "SET #status = :status, backup_alert_sent = :sent_time"
          ExpressionAttributeNames = {
            "#status" = "status"
          }
          ExpressionAttributeValues = {
            ":status" = {
              S = "BACKUP_SENT"
            }
            ":sent_time" = {
              "N.$" = "$$.State.EnteredTime"
            }
          }
        }
        ResultPath = null
        Next       = "WaitBackupResponse"
      }

      # Esperar respuesta del backup (10 minutos)
      WaitBackupResponse = {
        Type    = "Wait"
        Seconds = 600 # 10 minutos
        Next    = "CheckBackupAcknowledgment"
      }

      CheckBackupAcknowledgment = {
        Type     = "Task"
        Resource = aws_lambda_function.escalation.arn
        Parameters = {
          "alert_id.$"     = "$.alert_id"
          action           = "check_acknowledgment"
          escalation_level = "BACKUP"
        }
        ResultPath = "$.acknowledgment_check"
        Next       = "IsBackupAcknowledged"
      }

      IsBackupAcknowledged = {
        Type = "Choice"
        Choices = [
          {
            Variable      = "$.acknowledgment_check.acknowledged"
            BooleanEquals = true
            Next          = "AlertAcknowledgedSuccess"
          }
        ]
        Default = "EscalateToDepartmentHead"
      }

      # Estado 3: Escalar a jefe de departamento
      EscalateToDepartmentHead = {
        Type     = "Task"
        Resource = aws_lambda_function.escalation.arn
        Parameters = {
          "alert_id.$"     = "$.alert_id"
          "patient_name.$" = "$.patient_name"
          "test_name.$"    = "$.test_name"
          "value.$"        = "$.value"
          "criticality.$"  = "$.criticality"
          action           = "escalate"
          escalation_level = "DEPARTMENT_HEAD"
        }
        ResultPath = "$.dept_head_alert_result"
        Next       = "UpdateAlertStatusDeptHead"
      }

      UpdateAlertStatusDeptHead = {
        Type     = "Task"
        Resource = "arn:aws:states:::dynamodb:updateItem"
        Parameters = {
          TableName = aws_dynamodb_table.alerts.name
          Key = {
            alert_id = {
              "S.$" = "$.alert_id"
            }
            timestamp = {
              "N.$" = "$.timestamp"
            }
          }
          UpdateExpression = "SET #status = :status, dept_head_alert_sent = :sent_time"
          ExpressionAttributeNames = {
            "#status" = "status"
          }
          ExpressionAttributeValues = {
            ":status" = {
              S = "DEPT_HEAD_SENT"
            }
            ":sent_time" = {
              "N.$" = "$$.State.EnteredTime"
            }
          }
        }
        ResultPath = null
        Next       = "WaitDeptHeadResponse"
      }

      WaitDeptHeadResponse = {
        Type    = "Wait"
        Seconds = 900 # 15 minutos
        Next    = "CheckDeptHeadAcknowledgment"
      }

      CheckDeptHeadAcknowledgment = {
        Type     = "Task"
        Resource = aws_lambda_function.escalation.arn
        Parameters = {
          "alert_id.$"     = "$.alert_id"
          action           = "check_acknowledgment"
          escalation_level = "DEPT_HEAD"
        }
        ResultPath = "$.acknowledgment_check"
        Next       = "IsDeptHeadAcknowledged"
      }

      IsDeptHeadAcknowledged = {
        Type = "Choice"
        Choices = [
          {
            Variable      = "$.acknowledgment_check.acknowledged"
            BooleanEquals = true
            Next          = "AlertAcknowledgedSuccess"
          }
        ]
        Default = "EscalateToAdmin"
      }

      # Estado 4: Escalación final a administrador
      EscalateToAdmin = {
        Type     = "Task"
        Resource = "arn:aws:states:::sns:publish"
        Parameters = {
          TopicArn = aws_sns_topic.admin_alerts.arn
          Subject  = "CRITICAL: Unacknowledged Lab Alert - Maximum Escalation"
          Message = {
            "alert_id.$"     = "$.alert_id"
            "patient_name.$" = "$.patient_name"
            "test_name.$"    = "$.test_name"
            "value.$"        = "$.value"
            "criticality.$"  = "$.criticality"
            escalation_level = "ADMIN"
            message          = "CRITICAL ALERT has not been acknowledged after multiple escalations. Immediate administrative intervention required."
          }
        }
        ResultPath = "$.admin_alert_result"
        Next       = "UpdateAlertStatusAdmin"
      }

      UpdateAlertStatusAdmin = {
        Type     = "Task"
        Resource = "arn:aws:states:::dynamodb:updateItem"
        Parameters = {
          TableName = aws_dynamodb_table.alerts.name
          Key = {
            alert_id = {
              "S.$" = "$.alert_id"
            }
            timestamp = {
              "N.$" = "$.timestamp"
            }
          }
          UpdateExpression = "SET #status = :status, admin_alert_sent = :sent_time"
          ExpressionAttributeNames = {
            "#status" = "status"
          }
          ExpressionAttributeValues = {
            ":status" = {
              S = "ADMIN_ESCALATED"
            }
            ":sent_time" = {
              "N.$" = "$$.State.EnteredTime"
            }
          }
        }
        ResultPath = null
        Next       = "MaxEscalationReached"
      }

      # Estados terminales
      AlertAcknowledgedSuccess = {
        Type = "Succeed"
      }

      MaxEscalationReached = {
        Type = "Succeed"
      }

      AlertFailureNotification = {
        Type     = "Task"
        Resource = "arn:aws:states:::sns:publish"
        Parameters = {
          TopicArn = aws_sns_topic.alert_dlq.arn
          Subject  = "SYSTEM ERROR: Critical Alert Delivery Failed"
          Message = {
            "alert_id.$"  = "$.alert_id"
            "error_info.$" = "$.error_info"
            message       = "Failed to deliver critical alert. System intervention required."
          }
        }
        Next = "AlertFailed"
      }

      AlertFailed = {
        Type  = "Fail"
        Error = "AlertDeliveryFailed"
        Cause = "Failed to deliver critical alert through primary channel"
      }
    }
  })

  logging_configuration {
    log_destination        = "${aws_cloudwatch_log_group.step_functions.arn}:*"
    include_execution_data = true
    level                  = "ALL"
  }

  tracing_configuration {
    enabled = true
  }

  tags = merge(
    local.common_tags,
    {
      Name        = "${local.name_prefix}-escalation-workflow"
      Description = "State machine para escalación automática de alertas críticas"
    }
  )
}

# CloudWatch Log Group para Step Functions
resource "aws_cloudwatch_log_group" "step_functions" {
  name              = "/aws/stepfunctions/${local.name_prefix}-escalation-workflow"
  retention_in_days = var.log_retention_days

  tags = local.common_tags
}

# ============================================================================
# CLOUDWATCH ALARMS
# ============================================================================

# Alarm: Ejecuciones fallidas
resource "aws_cloudwatch_metric_alarm" "step_functions_failures" {
  alarm_name          = "${local.name_prefix}-step-functions-failures"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = 1
  metric_name         = "ExecutionsFailed"
  namespace           = "AWS/States"
  period              = 300
  statistic           = "Sum"
  threshold           = 0
  alarm_description   = "Alerta cuando hay ejecuciones fallidas en Step Functions"
  alarm_actions       = [aws_sns_topic.admin_alerts.arn]

  dimensions = {
    StateMachineArn = aws_sfn_state_machine.escalation_workflow.arn
  }

  tags = local.common_tags
}

# Alarm: Ejecuciones con timeout
resource "aws_cloudwatch_metric_alarm" "step_functions_timeout" {
  alarm_name          = "${local.name_prefix}-step-functions-timeout"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = 1
  metric_name         = "ExecutionsTimedOut"
  namespace           = "AWS/States"
  period              = 300
  statistic           = "Sum"
  threshold           = 0
  alarm_description   = "Alerta cuando hay ejecuciones con timeout"
  alarm_actions       = [aws_sns_topic.admin_alerts.arn]

  dimensions = {
    StateMachineArn = aws_sfn_state_machine.escalation_workflow.arn
  }

  tags = local.common_tags
}

# ============================================================================
# OUTPUTS
# ============================================================================

output "step_functions_info" {
  description = "Información de la State Machine"
  value = {
    arn  = aws_sfn_state_machine.escalation_workflow.arn
    name = aws_sfn_state_machine.escalation_workflow.name
  }
}