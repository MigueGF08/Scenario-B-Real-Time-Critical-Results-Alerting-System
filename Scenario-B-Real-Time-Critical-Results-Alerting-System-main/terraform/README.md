# CritAlert - Infraestructura Terraform

Sistema de alertas críticas de laboratorio con notificación automática y escalación inteligente.

## 📋 Tabla de Contenidos

- [Arquitectura](#arquitectura)
- [Prerequisitos](#prerequisitos)
- [Configuración Inicial](#configuración-inicial)
- [Despliegue](#despliegue)
- [Estructura del Proyecto](#estructura-del-proyecto)
- [Recursos Creados](#recursos-creados)
- [Variables de Configuración](#variables-de-configuración)
- [Testing](#testing)
- [Monitoreo](#monitoreo)
- [Troubleshooting](#troubleshooting)

---

## 🏗️ Arquitectura

```
┌─────────────────┐
│  API Gateway    │ ← Recibe resultados de lab
└────────┬────────┘
         ↓
┌─────────────────┐
│ Lambda Ingesta  │ ← Detecta criticidad
└────┬───────┬────┘
     │       │
CRÍTICO    NORMAL
     ↓       ↓
┌─────────┐ ┌──────────┐
│ Lambda  │ │   SQS    │
│ Alerta  │ │  Queue   │
└────┬────┘ └──────────┘
     ↓
┌─────────────────┐
│ Step Functions  │ ← Escalación automática
│  (Workflow)     │
└────┬────────────┘
     ↓
┌─────────────────┐
│  SNS → SMS      │
│  SNS → Push     │
│  SES → Email    │
└─────────────────┘
```

### Flujo de Escalación

1. **0-5 min**: Alerta al médico principal (SMS + Push + Email)
2. **5-15 min**: Si no responde → Escala al médico de respaldo
3. **15-30 min**: Si no responde → Escala al jefe de departamento
4. **30+ min**: Escala al administrador del hospital

---

## 🔧 Prerequisitos

### Software Requerido

- **Terraform** >= 1.0
- **AWS CLI** >= 2.0
- **Python** >= 3.11 (para funciones Lambda)
- **Git**

### Credenciales AWS

```bash
# Configurar credenciales AWS
aws configure

# Verificar configuración
aws sts get-caller-identity
```

### Permisos IAM Necesarios

Tu usuario AWS debe tener permisos para crear:
- Lambda Functions
- API Gateway
- DynamoDB Tables
- SNS Topics
- SQS Queues
- Step Functions
- CloudWatch (Logs, Alarms, Dashboards)
- IAM Roles y Políticas
- KMS Keys

---

## ⚙️ Configuración Inicial

### 1. Clonar el Repositorio

```bash
git clone <repo-url>
cd critalert/terraform
```

### 2. Crear Archivo de Variables

```bash
cp terraform.tfvars.example terraform.tfvars
```

### 3. Editar terraform.tfvars

```hcl
aws_region = "us-east-1"
environment = "dev"

# Configurar números de teléfono y emails
alert_phone_numbers = [
  "+15551234567"
]

alert_email_addresses = [
  "oncall@hospital.com"
]

emergency_admin_email = "admin@hospital.com"
```

### 4. Preparar Código Lambda

Asegúrate de tener el código Lambda en las carpetas correspondientes:

```
../lambda/
├── ingestion/
│   └── index.py
├── alert-handler/
│   └── index.py
├── normal-processor/
│   └── index.py
├── acknowledgment/
│   └── index.py
└── escalation/
    └── index.py
```

---

## 🚀 Despliegue

### Inicializar Terraform

```bash
terraform init
```

### Validar Configuración

```bash
terraform validate
```

### Ver Plan de Ejecución

```bash
terraform plan -out=plan.out
```

### Aplicar Cambios

```bash
# Desarrollo
terraform apply

# Producción (con confirmación explícita)
terraform apply plan.out
```

### Destruir Infraestructura (Solo Dev/Test)

```bash
terraform destroy
```

---

## 📁 Estructura del Proyecto

```
terraform/
├── main.tf                  # Configuración principal
├── variables.tf             # Definición de variables
├── outputs.tf               # Outputs del proyecto
├── api-gateway.tf           # API Gateway REST
├── lambda.tf                # Funciones Lambda
├── dynamodb.tf              # Tablas DynamoDB
├── sns.tf                   # Topics y subscripciones SNS
├── sqs.tf                   # Colas SQS
├── step-functions.tf        # State Machine de escalación
├── iam.tf                   # Roles y políticas IAM
├── cloudwatch.tf            # Dashboard y alarmas
├── terraform.tfvars.example # Ejemplo de configuración
├── .gitignore               # Archivos a ignorar
└── README.md                # Esta documentación
```

---

## 📦 Recursos Creados

### Compute
- **5 Lambda Functions**
  - Ingestion (router)
  - Critical Alert Handler
  - Normal Processor
  - Acknowledgment Handler
  - Escalation Handler

### API
- **1 API Gateway REST API**
  - POST /results
  - POST /alerts/{alertId}/acknowledge

### Storage
- **5 DynamoDB Tables**
  - critical_thresholds
  - alerts (con Streams)
  - physicians
  - lab_results
  - escalation_config

### Messaging
- **4 SNS Topics**
  - critical_alerts
  - escalated_alerts
  - admin_alerts
  - alert_dlq

- **2 SQS Queues**
  - normal_results
  - ordered_results (FIFO)

### Orchestration
- **1 Step Functions State Machine**
  - Escalation workflow

### Monitoring
- **1 CloudWatch Dashboard**
- **10+ CloudWatch Alarms**
- **4 Log Metric Filters**
- **3 CloudWatch Insights Queries**

### Security
- **2 KMS Keys** (SNS y SQS)
- **7 IAM Roles**

---

## 🔐 Variables de Configuración

### Variables Críticas

| Variable | Descripción | Valor Default |
|----------|-------------|---------------|
| `aws_region` | Región de despliegue | `us-east-1` |
| `environment` | Ambiente (dev/staging/prod) | `dev` |
| `alert_sla_seconds` | SLA para alertas críticas | `60` |
| `escalation_primary_minutes` | Tiempo antes de escalar | `5` |
| `alert_phone_numbers` | Números para SMS | `[]` |
| `alert_email_addresses` | Emails para alertas | `[]` |

### Umbrales Críticos

| Test | Valor Bajo | Valor Alto | Unidad |
|------|-----------|-----------|--------|
| Potasio | 2.5 | 6.0 | mmol/L |
| Glucosa | 40 | 500 | mg/dL |
| Hemoglobina | 5.0 | - | g/dL |
| Plaquetas | 20 | - | 10³/uL |
| Leucocitos | 1.0 | 50.0 | 10³/uL |

---

## 🧪 Testing

### 1. Confirmar Subscripciones SNS

Después del despliegue, verifica tu email y confirma las subscripciones SNS.

### 2. Poblar Tablas Base

```bash
# Ejecutar script de inicialización
cd ../scripts
python init_tables.py
```

### 3. Enviar Resultado de Prueba

```bash
curl -X POST https://API_GATEWAY_URL/dev/results \
  --aws-sigv4 "aws:amz:us-east-1:execute-api" \
  -H "Content-Type: application/json" \
  -d '{
    "patient_id": "P123456",
    "test_code": "K",
    "value": 6.8,
    "unit": "mmol/L",
    "ordering_physician": {
      "physician_id": "DR001",
      "name": "Dr. Test",
      "phone": "+15551234567"
    }
  }'
```

### 4. Verificar en CloudWatch

```bash
# Ver logs en tiempo real
aws logs tail /aws/lambda/critalert-dev-critical-alert-handler --follow
```

---

## 📊 Monitoreo

### Dashboard CloudWatch

Accede al dashboard en:
```
https://console.aws.amazon.com/cloudwatch/home?region=us-east-1#dashboards:name=critalert-dev-dashboard
```

### Métricas Clave

- **CriticalAlertsTriggered**: Total de alertas críticas
- **AlertLatencySeconds**: Tiempo de respuesta
- **SLACompliance**: % de alertas < 60 segundos
- **CriticalAlertsEscalated**: Alertas escaladas

### CloudWatch Insights Queries

```sql
-- Ver alertas fallidas
fields @timestamp, @message
| filter @message like /ERROR/
| filter @message like /ALERT_FAILED/
| sort @timestamp desc

-- Analizar latencia
fields @timestamp, latency_ms
| filter @message like /ALERT_SENT/
| stats avg(latency_ms) as avg_latency
```

---

## 🐛 Troubleshooting

### Error: "No se reciben alertas"

1. Verificar que las subscripciones SNS estén confirmadas
2. Revisar logs de Lambda: `/aws/lambda/critalert-dev-critical-alert-handler`
3. Verificar umbrales en DynamoDB `critical_thresholds`

### Error: "Lambda timeout"

1. Aumentar `lambda_timeout` en variables
2. Revisar concurrency limits
3. Verificar conectividad con DynamoDB/SNS

### Error: "Step Functions no escala"

1. Verificar permisos IAM del rol Step Functions
2. Revisar ejecuciones en consola Step Functions
3. Verificar que el workflow esté activo

### Error: "SQS backlog creciendo"

1. Aumentar concurrency de Lambda processor
2. Revisar errores en Lambda normal-processor
3. Verificar que el event source mapping esté habilitado

### Logs Útiles

```bash
# Lambda Ingestion
aws logs tail /aws/lambda/critalert-dev-ingestion --follow

# Lambda Alert Handler
aws logs tail /aws/lambda/critalert-dev-critical-alert-handler --follow

# Step Functions
aws logs tail /aws/stepfunctions/critalert-dev-escalation-workflow --follow

# API Gateway
aws logs tail /aws/apigateway/critalert --follow
```

---

## 📝 Notas Importantes

### Seguridad

- ❌ **NUNCA** subir `terraform.tfvars` a Git (contiene datos sensibles)
- ✅ Usar AWS Secrets Manager para credenciales
- ✅ Habilitar MFA en cuenta AWS
- ✅ Rotar KMS keys periódicamente

### Costos

**Estimado mensual (ambiente dev con 100 alertas/día):**
- Lambda: ~$5
- DynamoDB: ~$10
- API Gateway: ~$3
- SNS: ~$5
- SQS: ~$1
- CloudWatch: ~$10
- **Total: ~$35/mes**

**Producción (1000 alertas/día):**
- Estimado: ~$150-200/mes

### Cumplimiento

- HIPAA: ✅ Encriptación en reposo y tránsito
- Retención: 7 años para resultados de lab
- Auditoría: CloudWatch Logs con 90 días de retención

---

## 🆘 Soporte

Para problemas o preguntas:
- **Email**: devops@hospital.com
- **Slack**: #critalert-support
- **Documentación**: https://wiki.hospital.com/critalert

---

## 📄 Licencia

Copyright © 2024 Hospital. Todos los derechos reservados.