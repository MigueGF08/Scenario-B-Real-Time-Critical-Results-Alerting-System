# Tablas DynamoDB
# dynamodb.tf - Tablas de DynamoDB

# Tabla para almacenar umbrales críticos y reglas
resource "aws_dynamodb_table" "critical_thresholds" {
  name           = "${local.name_prefix}-critical-thresholds"
  billing_mode   = var.dynamodb_billing_mode
  hash_key       = "test_code"
  range_key      = "age_group"

  attribute {
    name = "test_code"
    type = "S"
  }

  attribute {
    name = "age_group"
    type = "S"
  }

  # TTL no necesario para esta tabla
  point_in_time_recovery {
    enabled = var.enable_point_in_time_recovery
  }

  server_side_encryption {
    enabled = true
  }

  tags = merge(
    local.common_tags,
    {
      Name        = "${local.name_prefix}-critical-thresholds"
      Description = "Tabla de umbrales críticos por prueba de laboratorio"
    }
  )
}

# Tabla para tracking de alertas y confirmaciones
resource "aws_dynamodb_table" "alerts" {
  name           = "${local.name_prefix}-alerts"
  billing_mode   = var.dynamodb_billing_mode
  hash_key       = "alert_id"
  range_key      = "timestamp"

  attribute {
    name = "alert_id"
    type = "S"
  }

  attribute {
    name = "timestamp"
    type = "N"
  }

  attribute {
    name = "physician_id"
    type = "S"
  }

  attribute {
    name = "status"
    type = "S"
  }

  # GSI para buscar alertas por médico
  global_secondary_index {
    name            = "PhysicianIndex"
    hash_key        = "physician_id"
    range_key       = "timestamp"
    projection_type = "ALL"
  }

  # GSI para buscar alertas por estado
  global_secondary_index {
    name            = "StatusIndex"
    hash_key        = "status"
    range_key       = "timestamp"
    projection_type = "ALL"
  }

  # TTL para limpieza automática de alertas antiguas (después de 90 días)
  ttl {
    attribute_name = "ttl"
    enabled        = true
  }

  # Stream para procesar cambios en tiempo real
  stream_enabled   = true
  stream_view_type = "NEW_AND_OLD_IMAGES"

  point_in_time_recovery {
    enabled = var.enable_point_in_time_recovery
  }

  server_side_encryption {
    enabled = true
  }

  tags = merge(
    local.common_tags,
    {
      Name        = "${local.name_prefix}-alerts"
      Description = "Tabla de tracking de alertas y confirmaciones"
    }
  )
}

# Tabla para almacenar información de médicos
resource "aws_dynamodb_table" "physicians" {
  name         = "${local.name_prefix}-physicians"
  billing_mode = var.dynamodb_billing_mode
  hash_key     = "physician_id"

  attribute {
    name = "physician_id"
    type = "S"
  }

  attribute {
    name = "department"
    type = "S"
  }

  # GSI para buscar médicos por departamento
  global_secondary_index {
    name            = "DepartmentIndex"
    hash_key        = "department"
    projection_type = "ALL"
  }

  point_in_time_recovery {
    enabled = var.enable_point_in_time_recovery
  }

  server_side_encryption {
    enabled = true
  }

  tags = merge(
    local.common_tags,
    {
      Name        = "${local.name_prefix}-physicians"
      Description = "Tabla de información de médicos y contactos"
    }
  )
}

# Tabla para resultados de laboratorio (histórico)
resource "aws_dynamodb_table" "lab_results" {
  name         = "${local.name_prefix}-lab-results"
  billing_mode = var.dynamodb_billing_mode
  hash_key     = "result_id"
  range_key    = "test_timestamp"

  attribute {
    name = "result_id"
    type = "S"
  }

  attribute {
    name = "test_timestamp"
    type = "N"
  }

  attribute {
    name = "patient_id"
    type = "S"
  }

  # GSI para buscar resultados por paciente
  global_secondary_index {
    name            = "PatientIndex"
    hash_key        = "patient_id"
    range_key       = "test_timestamp"
    projection_type = "ALL"
  }

  # TTL para limpieza automática después de 7 años (cumplimiento HIPAA)
  ttl {
    attribute_name = "ttl"
    enabled        = true
  }

  point_in_time_recovery {
    enabled = var.enable_point_in_time_recovery
  }

  server_side_encryption {
    enabled = true
  }

  tags = merge(
    local.common_tags,
    {
      Name        = "${local.name_prefix}-lab-results"
      Description = "Tabla de resultados de laboratorio históricos"
    }
  )
}

# Tabla para configuración de escalación
resource "aws_dynamodb_table" "escalation_config" {
  name         = "${local.name_prefix}-escalation-config"
  billing_mode = var.dynamodb_billing_mode
  hash_key     = "department"

  attribute {
    name = "department"
    type = "S"
  }

  point_in_time_recovery {
    enabled = var.enable_point_in_time_recovery
  }

  server_side_encryption {
    enabled = true
  }

  tags = merge(
    local.common_tags,
    {
      Name        = "${local.name_prefix}-escalation-config"
      Description = "Configuración de escalación por departamento"
    }
  )
}

# Outputs para las tablas
output "dynamodb_tables" {
  description = "ARNs de las tablas DynamoDB"
  value = {
    critical_thresholds = aws_dynamodb_table.critical_thresholds.arn
    alerts              = aws_dynamodb_table.alerts.arn
    physicians          = aws_dynamodb_table.physicians.arn
    lab_results         = aws_dynamodb_table.lab_results.arn
    escalation_config   = aws_dynamodb_table.escalation_config.arn
  }
}

output "alerts_table_stream_arn" {
  description = "ARN del stream de la tabla de alertas"
  value       = aws_dynamodb_table.alerts.stream_arn
}