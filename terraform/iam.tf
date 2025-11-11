# Roles y políticas IAM
# iam.tf - Roles y políticas IAM para todos los servicios

# ============================================================================
# ROL PARA LAMBDA: Ingesta de Resultados
# ============================================================================

resource "aws_iam_role" "lambda_ingestion" {
  name               = "${local.name_prefix}-lambda-ingestion-role"
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRole"
        Effect = "Allow"
        Principal = {
          Service = "lambda.amazonaws.com"
        }
      }
    ]
  })

  tags = merge(
    local.common_tags,
    {
      Name = "${local.name_prefix}-lambda-ingestion-role"
    }
  )
}

resource "aws_iam_role_policy" "lambda_ingestion_policy" {
  name = "${local.name_prefix}-lambda-ingestion-policy"
  role = aws_iam_role.lambda_ingestion.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "logs:CreateLogGroup",
          "logs:CreateLogStream",
          "logs:PutLogEvents"
        ]
        Resource = "arn:aws:logs:${local.region}:${local.account_id}:*"
      },
      {
        Effect = "Allow"
        Action = [
          "dynamodb:GetItem",
          "dynamodb:Query",
          "dynamodb:PutItem"
        ]
        Resource = [
          aws_dynamodb_table.critical_thresholds.arn,
          aws_dynamodb_table.lab_results.arn,
          "${aws_dynamodb_table.lab_results.arn}/index/*"
        ]
      },
      {
        Effect = "Allow"
        Action = [
          "sqs:SendMessage"
        ]
        Resource = aws_sqs_queue.normal_results.arn
      },
      {
        Effect = "Allow"
        Action = [
          "lambda:InvokeFunction"
        ]
        Resource = "arn:aws:lambda:${local.region}:${local.account_id}:function:${local.name_prefix}-critical-alert-handler"
      },
      {
        Effect = "Allow"
        Action = [
          "kms:Decrypt",
          "kms:GenerateDataKey"
        ]
        Resource = [
          aws_kms_key.sqs_encryption.arn
        ]
      }
    ]
  })
}

# ============================================================================
# ROL PARA LAMBDA: Manejo de Alertas Críticas
# ============================================================================

resource "aws_iam_role" "lambda_alert_handler" {
  name               = "${local.name_prefix}-lambda-alert-handler-role"
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRole"
        Effect = "Allow"
        Principal = {
          Service = "lambda.amazonaws.com"
        }
      }
    ]
  })

  tags = merge(
    local.common_tags,
    {
      Name = "${local.name_prefix}-lambda-alert-handler-role"
    }
  )
}

resource "aws_iam_role_policy" "lambda_alert_handler_policy" {
  name = "${local.name_prefix}-lambda-alert-handler-policy"
  role = aws_iam_role.lambda_alert_handler.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "logs:CreateLogGroup",
          "logs:CreateLogStream",
          "logs:PutLogEvents"
        ]
        Resource = "arn:aws:logs:${local.region}:${local.account_id}:*"
      },
      {
        Effect = "Allow"
        Action = [
          "dynamodb:GetItem",
          "dynamodb:PutItem",
          "dynamodb:UpdateItem",
          "dynamodb:Query"
        ]
        Resource = [
          aws_dynamodb_table.alerts.arn,
          aws_dynamodb_table.physicians.arn,
          aws_dynamodb_table.escalation_config.arn,
          "${aws_dynamodb_table.alerts.arn}/index/*",
          "${aws_dynamodb_table.physicians.arn}/index/*"
        ]
      },
      {
        Effect = "Allow"
        Action = [
          "sns:Publish"
        ]
        Resource = [
          aws_sns_topic.critical_alerts.arn,
          aws_sns_topic.escalated_alerts.arn,
          aws_sns_topic.admin_alerts.arn
        ]
      },
      {
        Effect = "Allow"
        Action = [
          "states:StartExecution"
        ]
        Resource = "arn:aws:states:${local.region}:${local.account_id}:stateMachine:${local.name_prefix}-escalation-workflow"
      },
      {
        Effect = "Allow"
        Action = [
          "kms:Decrypt",
          "kms:GenerateDataKey"
        ]
        Resource = [
          aws_kms_key.sns_encryption.arn
        ]
      }
    ]
  })
}

# ============================================================================
# ROL PARA LAMBDA: Procesamiento Normal (SQS Consumer)
# ============================================================================

resource "aws_iam_role" "lambda_normal_processor" {
  name               = "${local.name_prefix}-lambda-normal-processor-role"
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRole"
        Effect = "Allow"
        Principal = {
          Service = "lambda.amazonaws.com"
        }
      }
    ]
  })

  tags = merge(
    local.common_tags,
    {
      Name = "${local.name_prefix}-lambda-normal-processor-role"
    }
  )
}

resource "aws_iam_role_policy" "lambda_normal_processor_policy" {
  name = "${local.name_prefix}-lambda-normal-processor-policy"
  role = aws_iam_role.lambda_normal_processor.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "logs:CreateLogGroup",
          "logs:CreateLogStream",
          "logs:PutLogEvents"
        ]
        Resource = "arn:aws:logs:${local.region}:${local.account_id}:*"
      },
      {
        Effect = "Allow"
        Action = [
          "sqs:ReceiveMessage",
          "sqs:DeleteMessage",
          "sqs:GetQueueAttributes"
        ]
        Resource = aws_sqs_queue.normal_results.arn
      },
      {
        Effect = "Allow"
        Action = [
          "dynamodb:PutItem",
          "dynamodb:UpdateItem"
        ]
        Resource = aws_dynamodb_table.lab_results.arn
      },
      {
        Effect = "Allow"
        Action = [
          "kms:Decrypt"
        ]
        Resource = aws_kms_key.sqs_encryption.arn
      }
    ]
  })
}

# ============================================================================
# ROL PARA LAMBDA: Confirmación de Alertas
# ============================================================================

resource "aws_iam_role" "lambda_acknowledgment" {
  name               = "${local.name_prefix}-lambda-acknowledgment-role"
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRole"
        Effect = "Allow"
        Principal = {
          Service = "lambda.amazonaws.com"
        }
      }
    ]
  })

  tags = merge(
    local.common_tags,
    {
      Name = "${local.name_prefix}-lambda-acknowledgment-role"
    }
  )
}

resource "aws_iam_role_policy" "lambda_acknowledgment_policy" {
  name = "${local.name_prefix}-lambda-acknowledgment-policy"
  role = aws_iam_role.lambda_acknowledgment.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "logs:CreateLogGroup",
          "logs:CreateLogStream",
          "logs:PutLogEvents"
        ]
        Resource = "arn:aws:logs:${local.region}:${local.account_id}:*"
      },
      {
        Effect = "Allow"
        Action = [
          "dynamodb:GetItem",
          "dynamodb:UpdateItem",
          "dynamodb:Query"
        ]
        Resource = [
          aws_dynamodb_table.alerts.arn,
          "${aws_dynamodb_table.alerts.arn}/index/*"
        ]
      },
      {
        Effect = "Allow"
        Action = [
          "states:StopExecution",
          "states:DescribeExecution"
        ]
        Resource = "arn:aws:states:${local.region}:${local.account_id}:execution:${local.name_prefix}-escalation-workflow:*"
      }
    ]
  })
}

# ============================================================================
# ROL PARA API GATEWAY
# ============================================================================

resource "aws_iam_role" "api_gateway" {
  name               = "${local.name_prefix}-api-gateway-role"
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRole"
        Effect = "Allow"
        Principal = {
          Service = "apigateway.amazonaws.com"
        }
      }
    ]
  })

  tags = merge(
    local.common_tags,
    {
      Name = "${local.name_prefix}-api-gateway-role"
    }
  )
}

resource "aws_iam_role_policy" "api_gateway_policy" {
  name = "${local.name_prefix}-api-gateway-policy"
  role = aws_iam_role.api_gateway.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "logs:CreateLogGroup",
          "logs:CreateLogStream",
          "logs:PutLogEvents"
        ]
        Resource = "*"
      },
      {
        Effect = "Allow"
        Action = [
          "lambda:InvokeFunction"
        ]
        Resource = "arn:aws:lambda:${local.region}:${local.account_id}:function:${local.name_prefix}-*"
      }
    ]
  })
}

# ============================================================================
# ROL PARA STEP FUNCTIONS
# ============================================================================

resource "aws_iam_role" "step_functions" {
  name               = "${local.name_prefix}-step-functions-role"
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRole"
        Effect = "Allow"
        Principal = {
          Service = "states.amazonaws.com"
        }
      }
    ]
  })

  tags = merge(
    local.common_tags,
    {
      Name = "${local.name_prefix}-step-functions-role"
    }
  )
}

resource "aws_iam_role_policy" "step_functions_policy" {
  name = "${local.name_prefix}-step-functions-policy"
  role = aws_iam_role.step_functions.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "lambda:InvokeFunction"
        ]
        Resource = [
          "arn:aws:lambda:${local.region}:${local.account_id}:function:${local.name_prefix}-*"
        ]
      },
      {
        Effect = "Allow"
        Action = [
          "sns:Publish"
        ]
        Resource = [
          aws_sns_topic.critical_alerts.arn,
          aws_sns_topic.escalated_alerts.arn,
          aws_sns_topic.admin_alerts.arn
        ]
      },
      {
        Effect = "Allow"
        Action = [
          "dynamodb:GetItem",
          "dynamodb:PutItem",
          "dynamodb:UpdateItem"
        ]
        Resource = aws_dynamodb_table.alerts.arn
      },
      {
        Effect = "Allow"
        Action = [
          "logs:CreateLogDelivery",
          "logs:GetLogDelivery",
          "logs:UpdateLogDelivery",
          "logs:DeleteLogDelivery",
          "logs:ListLogDeliveries",
          "logs:PutResourcePolicy",
          "logs:DescribeResourcePolicies",
          "logs:DescribeLogGroups"
        ]
        Resource = "*"
      },
      {
        Effect = "Allow"
        Action = [
          "kms:Decrypt",
          "kms:GenerateDataKey"
        ]
        Resource = aws_kms_key.sns_encryption.arn
      }
    ]
  })
}

# ============================================================================
# ROL PARA CLOUDWATCH EVENTS/EVENTBRIDGE
# ============================================================================

resource "aws_iam_role" "eventbridge" {
  name               = "${local.name_prefix}-eventbridge-role"
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRole"
        Effect = "Allow"
        Principal = {
          Service = "events.amazonaws.com"
        }
      }
    ]
  })

  tags = merge(
    local.common_tags,
    {
      Name = "${local.name_prefix}-eventbridge-role"
    }
  )
}

resource "aws_iam_role_policy" "eventbridge_policy" {
  name = "${local.name_prefix}-eventbridge-policy"
  role = aws_iam_role.eventbridge.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "states:StartExecution"
        ]
        Resource = "arn:aws:states:${local.region}:${local.account_id}:stateMachine:${local.name_prefix}-*"
      }
    ]
  })
}

# ============================================================================
# OUTPUTS
# ============================================================================

output "iam_roles" {
  description = "ARNs de los roles IAM creados"
  value = {
    lambda_ingestion      = aws_iam_role.lambda_ingestion.arn
    lambda_alert_handler  = aws_iam_role.lambda_alert_handler.arn
    lambda_normal_processor = aws_iam_role.lambda_normal_processor.arn
    lambda_acknowledgment = aws_iam_role.lambda_acknowledgment.arn
    api_gateway           = aws_iam_role.api_gateway.arn
    step_functions        = aws_iam_role.step_functions.arn
    eventbridge           = aws_iam_role.eventbridge.arn
  }
}