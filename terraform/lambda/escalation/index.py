# lambda/escalation/index.py
import os
import json
import logging

import boto3
from boto3.dynamodb.conditions import Key

logger = logging.getLogger()
logger.setLevel(logging.INFO)

AWS_REGION = os.getenv("AWS_REGION_NAME") or os.getenv("AWS_REGION", "us-east-1")

dynamodb = boto3.resource("dynamodb", region_name=AWS_REGION)
sns = boto3.client("sns", region_name=AWS_REGION)

ALERTS_TABLE = os.environ["ALERTS_TABLE"]
PHYSICIANS_TABLE = os.environ["PHYSICIANS_TABLE"]
SNS_ESCALATED_TOPIC = os.environ["SNS_ESCALATED_TOPIC"]
SNS_ADMIN_TOPIC = os.environ["SNS_ADMIN_TOPIC"]  # posiblemente no usado directamente


def _get_latest_alert(alert_id: str):
    table = dynamodb.Table(ALERTS_TABLE)
    resp = table.query(
        KeyConditionExpression=Key("alert_id").eq(alert_id),
        ScanIndexForward=False,
        Limit=1,
    )
    items = resp.get("Items", [])
    return items[0] if items else None


def _handle_check_acknowledgment(event: dict) -> dict:
    alert_id = event["alert_id"]
    alert = _get_latest_alert(alert_id)
    if not alert:
        return {
            "alert_id": alert_id,
            "acknowledged": False,
            "reason": "NOT_FOUND",
        }

    acknowledged_at = alert.get("acknowledged_at")
    acknowledged = acknowledged_at is not None

    return {
        "alert_id": alert_id,
        "acknowledged": bool(acknowledged),
        "acknowledged_at": acknowledged_at,
    }


def _handle_escalate(event: dict) -> dict:
    alert_id = event["alert_id"]
    escalation_level = event.get("escalation_level", "UNKNOWN")
    patient_name = event.get("patient_name")
    test_name = event.get("test_name")
    value = event.get("value")
    criticality = event.get("criticality")
    previous_physician = event.get("previous_physician")

    message = {
        "alert_id": alert_id,
        "escalation_level": escalation_level,
        "patient_name": patient_name,
        "test_name": test_name,
        "value": value,
        "criticality": criticality,
        "previous_physician": previous_physician,
    }

    logger.info("Publishing escalation to SNS: %s", message)

    sns.publish(
        TopicArn=SNS_ESCALATED_TOPIC,
        Subject=f"[CritAlert] Escalation {escalation_level} for alert {alert_id}",
        Message=json.dumps(message, default=str),
    )

    return {"status": "ESCALATED", "alert_id": alert_id, "escalation_level": escalation_level}


def handler(event, context):
    logger.info("Event: %s", json.dumps(event, default=str))

    action = event.get("action")
    if action == "check_acknowledgment":
        return _handle_check_acknowledgment(event)
    elif action == "escalate":
        return _handle_escalate(event)
    else:
        raise ValueError(f"Unsupported action: {action}")
