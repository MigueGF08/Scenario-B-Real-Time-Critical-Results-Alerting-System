# lambda/ingestion/index.py
import os
import json
import logging
import uuid
import time
import base64
from datetime import datetime, timezone

import boto3
from boto3.dynamodb.conditions import Key

logger = logging.getLogger()
logger.setLevel(logging.INFO)

AWS_REGION = os.getenv("AWS_REGION_NAME") or os.getenv("AWS_REGION", "us-east-1")

dynamodb = boto3.resource("dynamodb", region_name=AWS_REGION)
sqs = boto3.client("sqs", region_name=AWS_REGION)
lambda_client = boto3.client("lambda", region_name=AWS_REGION)

THRESHOLDS_TABLE = os.environ["THRESHOLDS_TABLE"]
LAB_RESULTS_TABLE = os.environ["LAB_RESULTS_TABLE"]
NORMAL_RESULTS_QUEUE = os.environ["NORMAL_RESULTS_QUEUE"]
CRITICAL_ALERT_FUNCTION = os.environ["CRITICAL_ALERT_FUNCTION"]
ALERT_SLA_SECONDS = int(os.getenv("ALERT_SLA_SECONDS", "600"))


def _response(status_code: int, body: dict):
    return {
        "statusCode": status_code,
        "headers": {
            "Content-Type": "application/json"
        },
        "body": json.dumps(body, default=str),
    }


def _parse_body_from_api_gateway(event):
    body = event.get("body") or "{}"
    if event.get("isBase64Encoded"):
        body = base64.b64decode(body).decode("utf-8")
    try:
        return json.loads(body)
    except json.JSONDecodeError:
        raise ValueError("Invalid JSON body")


def _determine_age_group(age: int) -> str:
    if age < 18:
        return "pediatric"
    if age < 65:
        return "adult"
    return "elderly"


def _get_threshold_for_result(test_code: str, age: int):
    """
    Busca en DynamoDB la fila de umbrales críticos:
    - PK: test_code
    - SK: age_group
    Se asume que el item tiene atributos: critical_low, critical_high
    """
    table = dynamodb.Table(THRESHOLDS_TABLE)
    age_group = _determine_age_group(age)

    resp = table.get_item(
        Key={
            "test_code": test_code,
            "age_group": age_group,
        }
    )
    item = resp.get("Item")
    if not item:
        logger.warning("No thresholds found for test_code=%s age_group=%s", test_code, age_group)
        return None

    return {
        "age_group": age_group,
        "critical_low": float(item.get("critical_low", 0.0)),
        "critical_high": float(item.get("critical_high", 0.0)),
    }


def _evaluate_criticality(value: float, thresholds: dict | None) -> tuple[bool, str]:
    if not thresholds:
        # Sin umbrales configurados => tratamos como no crítico pero lo dejamos logueado
        return False, "NO_THRESHOLDS"

    low = thresholds["critical_low"]
    high = thresholds["critical_high"]

    if value < low:
        return True, "CRITICAL_LOW"
    if value > high:
        return True, "CRITICAL_HIGH"
    return False, "NORMAL"


def _store_lab_result(lab_result: dict) -> dict:
    """
    Inserta el resultado en la tabla lab_results.
    Clave:
    - result_id (S)
    - test_timestamp (N, epoch seconds)
    """
    table = dynamodb.Table(LAB_RESULTS_TABLE)

    now_epoch = int(time.time())
    result_id = str(uuid.uuid4())

    # Parseamos timestamp ISO8601 si viene; si no, usamos ahora
    ts_str = lab_result.get("test_timestamp")
    if ts_str:
        try:
            dt = datetime.fromisoformat(ts_str.replace("Z", "+00:00"))
            test_epoch = int(dt.timestamp())
        except Exception:
            logger.warning("Invalid test_timestamp '%s', using now()", ts_str)
            test_epoch = now_epoch
    else:
        test_epoch = now_epoch

    item = {
        "result_id": result_id,
        "test_timestamp": test_epoch,
        "patient_id": lab_result.get("patient_id"),
        "patient_name": lab_result.get("patient_name"),
        "patient_age": int(lab_result.get("patient_age", 0)),
        "test_code": lab_result.get("test_code"),
        "test_name": lab_result.get("test_name"),
        "value": float(lab_result.get("value")),
        "unit": lab_result.get("unit"),
        "reference_range": lab_result.get("reference_range"),
        "ordering_physician": lab_result.get("ordering_physician", {}),
        "raw_payload": lab_result,
        "created_at": now_epoch,
    }

    table.put_item(Item=item)
    return item


def _send_to_normal_queue(lab_record: dict):
    sqs.send_message(
        QueueUrl=NORMAL_RESULTS_QUEUE,
        MessageBody=json.dumps(
            {
                "result_id": lab_record["result_id"],
                "test_timestamp": lab_record["test_timestamp"],
                "patient_id": lab_record.get("patient_id"),
                "test_code": lab_record.get("test_code"),
                "value": lab_record.get("value"),
            }
        ),
    )


def _invoke_critical_alert_handler(lab_record: dict, thresholds: dict | None, criticality: str):
    payload = {
        "lab_result": lab_record,
        "thresholds": thresholds,
        "criticality": criticality,
        "received_at": int(time.time()),
        "sla_seconds": ALERT_SLA_SECONDS,
    }
    logger.info("Invoking critical alert handler: %s", CRITICAL_ALERT_FUNCTION)

    lambda_client.invoke(
        FunctionName=CRITICAL_ALERT_FUNCTION,
        InvocationType="Event",  # async
        Payload=json.dumps(payload).encode("utf-8"),
    )


def handler(event, context):
    logger.info("Event: %s", json.dumps(event, default=str))

    # Asumimos invocación desde API Gateway (proxy)
    try:
        body = _parse_body_from_api_gateway(event)
    except ValueError as e:
        logger.exception("Bad request: %s", e)
        return _response(400, {"message": str(e)})

    required_fields = [
        "patient_id",
        "patient_name",
        "patient_age",
        "test_code",
        "test_name",
        "value",
        "unit",
        "reference_range",
        "ordering_physician",
    ]
    missing = [f for f in required_fields if f not in body]
    if missing:
        return _response(400, {"message": f"Missing fields: {', '.join(missing)}"})

    try:
        value = float(body["value"])
        age = int(body["patient_age"])
    except Exception:
        return _response(400, {"message": "Invalid numeric fields (value, patient_age)"})

    # Guardamos el resultado bruto en DynamoDB
    lab_record = _store_lab_result(body)

    # Evaluamos criticidad
    thresholds = _get_threshold_for_result(body["test_code"], age)
    is_critical, criticality = _evaluate_criticality(value, thresholds)

    if is_critical:
        _invoke_critical_alert_handler(lab_record, thresholds, criticality)
    else:
        _send_to_normal_queue(lab_record)

    return _response(
        202,
        {
            "message": "Lab result processed",
            "result_id": lab_record["result_id"],
            "critical": is_critical,
            "criticality": criticality,
        },
    )
