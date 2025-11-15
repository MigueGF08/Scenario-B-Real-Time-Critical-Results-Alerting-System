# lambda/normal-processor/index.py
import os
import json
import logging
import time

import boto3
from boto3.dynamodb.conditions import Key

logger = logging.getLogger()
logger.setLevel(logging.INFO)

AWS_REGION = os.getenv("AWS_REGION_NAME") or os.getenv("AWS_REGION", "us-east-1")

dynamodb = boto3.resource("dynamodb", region_name=AWS_REGION)
LAB_RESULTS_TABLE = os.environ["LAB_RESULTS_TABLE"]


def handler(event, context):
    logger.info("SQS Event: %s", json.dumps(event, default=str))

    table = dynamodb.Table(LAB_RESULTS_TABLE)
    now_epoch = int(time.time())

    for record in event.get("Records", []):
        try:
            body_str = record.get("body", "{}")
            data = json.loads(body_str)
            result_id = data["result_id"]
            test_timestamp = int(data["test_timestamp"])

            table.update_item(
                Key={
                    "result_id": result_id,
                    "test_timestamp": test_timestamp,
                },
                UpdateExpression="SET processed_at = :ts",
                ExpressionAttributeValues={":ts": now_epoch},
            )

            logger.info("Marked normal result processed: %s", result_id)

        except Exception as e:
            logger.exception("Error processing SQS record: %s", e)
            # dejar que falle → SQS reintenta según configuración

    return {"status": "OK"}
