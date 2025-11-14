# lambda/alert-handler/index.py
import os
import json
import logging
import uuid
import time

import boto3

logger = logging.getLogger()
logger.setLevel(logging.INFO)

AWS_REGION = os.getenv("AWS_REGION_NAME") or os.getenv("AWS_REGION", "us-east-1")

dynamodb = boto3.resource("dynamodb", region_name=AWS_REGION)
stepfunctions = boto3.client("stepfunctions", region_name=AWS_REGION)

ALERTS_TABLE = os.environ["ALERTS_TABLE"]
ESCALATION_STATE_MACHINE = os.environ["ESCALATION_STATE_MACHINE"]
ENVIRONMENT = os.getenv("ENVIRONMENT", "dev")


def handler(event, context):
    logger.info("Event: %s", json.dumps(event, default=str))

    lab_result = event.get("lab_result") or {}
    thresholds = event.get("thresholds") or {}
    criticality = event.get("criticality", "CRITICAL")
    sla_seconds = int(event.get("sla_seconds", 600))

    # Validación mínima
    required = ["patient_id", "patient_name", "test_code", "test_name", "value", "ordering_physician"]
    missing = [f for f in required if f not in lab_result]
    if missing:
        logger.error("Missing lab_result fields: %s", missing)
        raise ValueError(f"Missing lab_result fields: {', '.join(missing)}")

    now_epoch = int(time.time())
    alert_id = str(uuid.uuid4())

    alerts_table = dynamodb.Table(ALERTS_TABLE)

    ttl = now_epoch + 60 * 60 * 24 * 30  # 30 días

    item = {
        "alert_id": alert_id,
        "timestamp": now_epoch,
        "patient_id": lab_result["patient_id"],
        "patient_name": lab_result["patient_name"],
        "patient_age": int(lab_result.get("patient_age", 0)),
        "test_code": lab_result["test_code"],
        "test_name": lab_result["test_name"],
        "value": float(lab_result["value"]),
        "unit": lab_result.get("unit"),
        "reference_range": lab_result.get("reference_range"),
        "ordering_physician": lab_result.get("ordering_physician", {}),
        "criticality": criticality,
        "thresholds": thresholds,
        "status": "NEW",
        "sla_seconds": sla_seconds,
        "environment": ENVIRONMENT,
        "ttl": ttl,
    }

    alerts_table.put_item(Item=item)
    logger.info("Alert stored with id=%s", alert_id)

    # Input para la state machine (debe contener los campos que el JSON de Step Functions usa)
    sf_input = {
        "alert_id": alert_id,
        "timestamp": now_epoch,
        "patient_id": lab_result["patient_id"],
        "patient_name": lab_result["patient_name"],
        "test_code": lab_result["test_code"],
        "test_name": lab_result["test_name"],
        "value": float(lab_result["value"]),
        "unit": lab_result.get("unit"),
        "criticality": criticality,
        "ordering_physician": lab_result.get("ordering_physician", {}),
        "sla_seconds": sla_seconds,
    }

    # Nombre único de ejecución
    execution_name = f"{alert_id}-{now_epoch}"

    resp = stepfunctions.start_execution(
        stateMachineArn=ESCALATION_STATE_MACHINE,
        name=execution_name[:80],
        input=json.dumps(sf_input),
    )

    logger.info("Started escalation workflow: %s", resp["executionArn"])

    return {
        "alert_id": alert_id,
        "execution_arn": resp["executionArn"],
        "status": "STARTED",
    }
