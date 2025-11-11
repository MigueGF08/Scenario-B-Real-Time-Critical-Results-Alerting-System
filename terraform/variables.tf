 # Variables de entrada
 # variables.tf - Definición de variables

# Configuración básica
variable "aws_region" {
  description = "Región de AWS donde se desplegará la infraestructura"
  type        = string
  default     = "us-east-1"
}

variable "environment" {
  description = "Ambiente de despliegue (dev, staging, prod)"
  type        = string
  default     = "dev"
  
  validation {
    condition     = contains(["dev", "staging", "prod"], var.environment)
    error_message = "El ambiente debe ser dev, staging o prod"
  }
}

variable "project_owner" {
  description = "Email o nombre del dueño del proyecto"
  type        = string
  default     = "devops@hospital.com"
}

# Configuración de alertas
variable "alert_sla_seconds" {
  description = "SLA para envío de alertas críticas (segundos)"
  type        = number
  default     = 60
}

variable "escalation_primary_minutes" {
  description = "Minutos antes de escalar al médico backup"
  type        = number
  default     = 5
}

variable "escalation_secondary_minutes" {
  description = "Minutos antes de escalar al jefe de departamento"
  type        = number
  default     = 10
}

variable "escalation_tertiary_minutes" {
  description = "Minutos antes de escalar al administrador"
  type        = number
  default     = 15
}

# Configuración de notificaciones
variable "alert_phone_numbers" {
  description = "Lista de números de teléfono para alertas SMS (formato: +1234567890)"
  type        = list(string)
  default     = []
  sensitive   = true
}

variable "alert_email_addresses" {
  description = "Lista de emails para notificaciones"
  type        = list(string)
  default     = []
  sensitive   = true
}

variable "emergency_admin_email" {
  description = "Email del administrador de emergencias"
  type        = string
  default     = "admin@hospital.com"
  sensitive   = true
}

# Configuración de Lambda
variable "lambda_runtime" {
  description = "Runtime para las funciones Lambda"
  type        = string
  default     = "python3.11"
}

variable "lambda_timeout" {
  description = "Timeout por defecto para Lambdas (segundos)"
  type        = number
  default     = 30
}

variable "lambda_memory_size" {
  description = "Memoria asignada a Lambdas (MB)"
  type        = number
  default     = 256
}

# Configuración de DynamoDB
variable "dynamodb_billing_mode" {
  description = "Modo de facturación de DynamoDB (PROVISIONED o PAY_PER_REQUEST)"
  type        = string
  default     = "PAY_PER_REQUEST"
}

variable "enable_point_in_time_recovery" {
  description = "Habilitar recuperación point-in-time para DynamoDB"
  type        = bool
  default     = true
}

# Configuración de SQS
variable "sqs_visibility_timeout" {
  description = "Timeout de visibilidad para mensajes en SQS (segundos)"
  type        = number
  default     = 300
}

variable "sqs_message_retention" {
  description = "Retención de mensajes en SQS (segundos, máximo 14 días)"
  type        = number
  default     = 1209600 # 14 días
}

# Configuración de CloudWatch
variable "enable_detailed_monitoring" {
  description = "Habilitar monitoreo detallado de CloudWatch"
  type        = bool
  default     = true
}

variable "log_retention_days" {
  description = "Días de retención para logs de CloudWatch"
  type        = number
  default     = 30
}

# Configuración de umbrales críticos (se pueden sobreescribir)
variable "critical_thresholds" {
  description = "Umbrales críticos para valores de laboratorio"
  type = object({
    potassium_low      = number
    potassium_high     = number
    glucose_low        = number
    glucose_high       = number
    hemoglobin_low     = number
    platelet_count_low = number
    wbc_low            = number
    wbc_high           = number
  })
  default = {
    potassium_low      = 2.5
    potassium_high     = 6.0
    glucose_low        = 40
    glucose_high       = 500
    hemoglobin_low     = 5.0
    platelet_count_low = 20
    wbc_low            = 1.0
    wbc_high           = 50.0
  }
}

# Feature flags
variable "enable_phone_alerts" {
  description = "Habilitar alertas por llamada telefónica (requiere Amazon Connect)"
  type        = bool
  default     = false
}

variable "enable_backup_region" {
  description = "Habilitar región de backup para alta disponibilidad"
  type        = bool
  default     = false
}

variable "backup_region" {
  description = "Región de AWS para backup (si está habilitado)"
  type        = string
  default     = "us-west-2"
}