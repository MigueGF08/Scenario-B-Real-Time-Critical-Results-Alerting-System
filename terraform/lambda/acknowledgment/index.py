# lambda/acknowledgment/index.py
import os
import json
import logging
import time
import base64

import boto3
from boto3.dynamodb.conditions import Key

logger = logging.getLogger()
logger.setLevel(logging.INFO)

AWS_REGION = os.getenv("AWS_REGION_NAME") or os.getenv("AWS_REGION", "us-east-1")

dynamodb = boto3.resource("dynamodb", region_name=AWS_REGION)
ALERTS_TABLE = os.environ["ALERTS_TABLE"]


def _response(status_code: int, body: dict):
    return {
        "statusCode": status_code,
        "headers": {
            "Content-Type": "application/json"
        },
        "body": json.dumps(body, default=str),
    }


def _parse_body(event):
    body = event.get("body") or "{}"
    if event.get("isBase64Encoded"):
        body = base64.b64decode(body).decode("utf-8")
    try:
        return json.loads(body)
    except json.JSONDecodeError:
        return {}


def handler(event, context):
    logger.info("Event: %s", json.dumps(event, default=str))

    path_params = event.get("pathParameters") or {}
    alert_id = path_params.get("alertId") or path_params.get("alert_id")
    if not alert_id:
        return _response(400, {"message": "Missing alertId in path"})

    body = _parse_body(event)
    channel = body.get("channel", "unknown")
    acknowledged_by = body.get("physician_id") or body.get("user_id") or "unknown"
    note = body.get("note", "")

    table = dynamodb.Table(ALERTS_TABLE)

    # Obtenemos el item más reciente para ese alert_id
    query_resp = table.query(
        KeyConditionExpression=Key("alert_id").eq(alert_id),
        ScanIndexForward=False,  # más nuevo primero
        Limit=1,
    )
    items = query_resp.get("Items", [])
    if not items:
        return _response(404, {"message": "Alert not found", "alert_id": alert_id})

    item = items[0]
    timestamp = item["timestamp"]
    now_epoch = int(time.time())

    table.update_item(
        Key={"alert_id": alert_id, "timestamp": timestamp},
        UpdateExpression=(
            "SET #status = :status, "
            "acknowledged_at = :ack_ts, "
            "acknowledged_by = :ack_by, "
            "acknowledged_channel = :channel, "
            "acknowledgment_note = :note"
        ),
        ExpressionAttributeNames={"#status": "status"},
        ExpressionAttributeValues={
            ":status": "ACKNOWLEDGED",
            ":ack_ts": now_epoch,
            ":ack_by": acknowledged_by,
            ":channel": channel,
            ":note": note,
        },
    )

    return _response(
        200,
        {
            "message": "Alert acknowledged",
            "alert_id": alert_id,
            "status": "ACKNOWLEDGED",
            "acknowledged_at": now_epoch,
            "acknowledged_by": acknowledged_by,
            "channel": channel,
        },
    )
