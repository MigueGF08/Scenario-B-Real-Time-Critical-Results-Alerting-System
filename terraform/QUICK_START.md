# 🚀 CritAlert - Guía Rápida de Inicio

## Setup en 5 Minutos

### 1️⃣ Preparar Entorno

```bash
# Clonar repositorio
git clone <repo-url>
cd critalert/terraform

# Verificar Terraform
terraform version  # debe ser >= 1.0

# Verificar AWS CLI
aws sts get-caller-identity
```

### 2️⃣ Configurar Variables

```bash
# Copiar ejemplo de variables
cp terraform.tfvars.example terraform.tfvars

# Editar con tus valores
nano terraform.tfvars
```

**Valores mínimos requeridos:**
```hcl
aws_region = "us-east-1"
environment = "dev"
alert_phone_numbers = ["+15551234567"]
alert_email_addresses = ["oncall@hospital.com"]
emergency_admin_email = "admin@hospital.com"
```

### 3️⃣ Desplegar Infraestructura

```bash
# Inicializar Terraform
terraform init

# Ver plan
terraform plan

# Aplicar cambios
terraform apply -auto-approve
```

⏱️ **Tiempo estimado**: 3-5 minutos

### 4️⃣ Configuración Post-Despliegue

```bash
# 1. Confirmar subscripciones SNS en tu email

# 2. Obtener URL del API
terraform output api_gateway

# 3. Ver dashboard
terraform output cloudwatch_dashboard_url
```

---

## 📊 Verificar Despliegue

### Check 1: Recursos Creados

```bash
# Ver todos los outputs
terraform output

# Verificar Lambdas
aws lambda list-functions --query 'Functions[?starts_with(FunctionName, `critalert`)].FunctionName'

# Verificar Tablas DynamoDB
aws dynamodb list-tables --query 'TableNames[?starts_with(@, `critalert`)]'
```

### Check 2: Health Check

```bash
# Invocar Lambda de prueba
aws lambda invoke \
  --function-name critalert-dev-ingestion \
  --payload '{"test": true}' \
  response.json

cat response.json
```

### Check 3: Logs

```bash
# Ver logs recientes
aws logs tail /aws/lambda/critalert-dev-critical-alert-handler --since 5m
```

---

## 🧪 Test Básico

### Enviar Alerta de Prueba

```bash
# Obtener API URL
API_URL=$(terraform output -raw api_gateway | jq -r '.base_url')

# Enviar resultado crítico
curl -X POST ${API_URL}/results \
  --aws-sigv4 "aws:amz:us-east-1:execute-api" \
  -H "Content-Type: application/json" \
  -d '{
    "patient_id": "P123456",
    "patient_name": "John Test",
    "patient_age": 65,
    "test_code": "K",
    "test_name": "Potassium",
    "value": 6.8,
    "unit": "mmol/L",
    "reference_range": "3.5-5.0",
    "ordering_physician": {
      "physician_id": "DR001",
      "name": "Dr. Test",
      "phone": "+15551234567",
      "email": "test@hospital.com"
    },
    "test_timestamp": "'$(date -u +%Y-%m-%dT%H:%M:%SZ)'"
  }'
```

**Resultado esperado:**
- ✅ SMS enviado al número configurado
- ✅ Email recibido
- ✅ Entrada en DynamoDB `alerts`
- ✅ Step Function iniciado

---

## 📈 Monitoreo Rápido

### Dashboard

```bash
# Abrir dashboard en navegador
open "$(terraform output -raw cloudwatch_dashboard_url)"
```

### Métricas Clave

```bash
# Alertas críticas última hora
aws cloudwatch get-metric-statistics \
  --namespace CritAlert \
  --metric-name CriticalAlertsTriggered \
  --start-time $(date -u -d '1 hour ago' +%Y-%m-%dT%H:%M:%S) \
  --end-time $(date -u +%Y-%m-%dT%H:%M:%S) \
  --period 3600 \
  --statistics Sum
```

### Ver Alertas Activas

```bash
# Alertas en DynamoDB
aws dynamodb scan \
  --table-name critalert-dev-alerts \
  --filter-expression "attribute_not_exists(acknowledged_at)" \
  --max-items 10
```

---

## 🔄 Updates Comunes

### Cambiar Umbrales Críticos

```bash
# Editar terraform.tfvars
nano terraform.tfvars

# Buscar critical_thresholds y modificar valores
# Aplicar cambios
terraform apply -auto-approve
```

### Agregar Números de Teléfono

```bash
# En terraform.tfvars
alert_phone_numbers = [
  "+15551234567",
  "+15559876543"  # Nuevo número
]

terraform apply -auto-approve
```

### Cambiar Tiempos de Escalación

```bash
# En terraform.tfvars
escalation_primary_minutes = 3    # Cambiar de 5 a 3 minutos
escalation_secondary_minutes = 8  # Cambiar de 10 a 8 minutos

terraform apply -auto-approve
```

---

## 🧹 Limpieza (Solo Dev)

```bash
# ADVERTENCIA: Esto eliminará TODOS los recursos
terraform destroy -auto-approve

# Confirmación
Are you sure? (yes/no): yes
```

---

## 🆘 Solución Rápida de Problemas

### No recibo alertas

```bash
# 1. Verificar subscripciones SNS
aws sns list-subscriptions --query 'Subscriptions[?starts_with(TopicArn, `arn:aws:sns:*:*:critalert`)]'

# 2. Ver logs de Lambda
aws logs tail /aws/lambda/critalert-dev-critical-alert-handler --follow

# 3. Verificar permisos
aws iam get-role --role-name critalert-dev-lambda-alert-handler-role
```

### Lambda con errores

```bash
# Ver últimos errores
aws logs filter-log-events \
  --log-group-name /aws/lambda/critalert-dev-critical-alert-handler \
  --filter-pattern "ERROR" \
  --start-time $(date -u -d '1 hour ago' +%s)000

# Aumentar timeout si es necesario
# En terraform.tfvars:
lambda_timeout = 60
```

### Step Functions no escala

```bash
# Ver ejecuciones fallidas
aws stepfunctions list-executions \
  --state-machine-arn $(terraform output -raw step_functions_info | jq -r '.escalation_workflow.arn') \
  --status-filter FAILED

# Ver detalles de una ejecución
aws stepfunctions describe-execution \
  --execution-arn <ARN_FROM_ABOVE>
```

---

## 📋 Checklist de Producción

Antes de pasar a producción:

- [ ] Cambiar `environment = "prod"` en terraform.tfvars
- [ ] Configurar todos los números de teléfono reales
- [ ] Confirmar todas las subscripciones SNS
- [ ] Poblar tabla `physicians` con datos reales
- [ ] Configurar tabla `critical_thresholds` con valores validados
- [ ] Configurar tabla `escalation_config` por departamento
- [ ] Habilitar `enable_point_in_time_recovery = true`
- [ ] Aumentar `log_retention_days = 90`
- [ ] Configurar alarmas con números de guardia
- [ ] Realizar pruebas end-to-end
- [ ] Documentar procedimiento de escalación
- [ ] Entrenar al personal médico
- [ ] Configurar backup en otra región

---

## 📚 Próximos Pasos

1. **Leer documentación completa**: `README.md`
2. **Configurar datos iniciales**: Scripts en `../scripts/`
3. **Desarrollar código Lambda**: Ver `../lambda/README.md`
4. **Integración con sistema de lab**: Ver documentación de API

---

## 💡 Tips Útiles

```bash
# Alias útiles (agregar a ~/.bashrc)
alias tf='terraform'
alias tfa='terraform apply -auto-approve'
alias tfp='terraform plan'
alias tfo='terraform output'
alias awsl='aws logs tail --follow'

# Ver estado de recursos
terraform show

# Formatear archivos
terraform fmt

# Validar sintaxis
terraform validate

# Ver gráfico de dependencias
terraform graph | dot -Tpng > graph.png
```

---

## 🔗 Links Importantes

- **Dashboard**: Ejecuta `terraform output cloudwatch_dashboard_url`
- **API Gateway**: Ejecuta `terraform output api_endpoints`
- **Step Functions**: https://console.aws.amazon.com/states/home?region=us-east-1
- **DynamoDB**: https://console.aws.amazon.com/dynamodbv2/home?region=us-east-1

---

**¿Problemas?** Revisa `README.md` sección Troubleshooting o contacta a devops@hospital.com