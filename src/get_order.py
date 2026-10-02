import json
import os
from decimal import Decimal

import boto3

dynamodb = boto3.resource("dynamodb")


def _json_default(value):
    if isinstance(value, Decimal):
        return str(value)
    raise TypeError(f"Unsupported value: {type(value)}")


def lambda_handler(event, context):
    order_id = (event.get("pathParameters") or {}).get("order_id")
    if not order_id:
        return {"statusCode": 400, "body": json.dumps({"message": "order_id is required"})}

    response = dynamodb.Table(os.environ["ORDERS_TABLE_NAME"]).get_item(Key={"order_id": order_id})
    item = response.get("Item")
    if not item:
        return {"statusCode": 404, "headers": {"Content-Type": "application/json"}, "body": json.dumps({"message": "order not processed yet"})}
    return {"statusCode": 200, "headers": {"Content-Type": "application/json"}, "body": json.dumps(item, default=_json_default)}
