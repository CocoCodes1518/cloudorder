import json
import os
from datetime import UTC, datetime

import boto3
from botocore.exceptions import ClientError

dynamodb = boto3.resource("dynamodb")
eventbridge = boto3.client("events")


def lambda_handler(event, context):
    table = dynamodb.Table(os.environ["ORDERS_TABLE_NAME"])
    for record in event["Records"]:
        order = json.loads(record["body"])
        try:
            table.put_item(
                Item={**order, "status": "PROCESSED", "processed_at": datetime.now(UTC).isoformat()},
                ConditionExpression="attribute_not_exists(order_id)",
            )
            eventbridge.put_events(Entries=[{
                "Source": "cloudorder.processor",
                "DetailType": "OrderProcessed",
                "Detail": json.dumps({"order_id": order["order_id"]}),
                "EventBusName": os.environ["EVENT_BUS_NAME"],
            }])
            print(json.dumps({"event": "order_processed", "order_id": order["order_id"]}))
        except ClientError as error:
            if error.response["Error"]["Code"] == "ConditionalCheckFailedException":
                print(json.dumps({"event": "duplicate_ignored", "order_id": order["order_id"]}))
                continue
            raise
