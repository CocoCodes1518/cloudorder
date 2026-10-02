import json
import os
import uuid
from datetime import UTC, datetime
from decimal import Decimal, InvalidOperation

import boto3

sqs = boto3.client("sqs")
eventbridge = boto3.client("events")


def _response(status_code: int, body: dict) -> dict:
    return {
        "statusCode": status_code,
        "headers": {"Content-Type": "application/json"},
        "body": json.dumps(body, default=str),
    }


def validate_order(payload: dict) -> tuple[bool, str | None, Decimal | None]:
    if not isinstance(payload.get("customer_id"), str) or not payload["customer_id"].strip():
        return False, "customer_id must be a non-empty string", None
    items = payload.get("items")
    if not isinstance(items, list) or not items:
        return False, "items must be a non-empty list", None

    total = Decimal("0")
    for item in items:
        if not isinstance(item, dict) or not isinstance(item.get("sku"), str) or not item["sku"].strip():
            return False, "every item needs a non-empty sku", None
        if not isinstance(item.get("quantity"), int) or item["quantity"] < 1:
            return False, "every item quantity must be a positive integer", None
        try:
            price = Decimal(str(item["unit_price"]))
            if not price.is_finite() or price < 0:
                raise InvalidOperation
        except (KeyError, InvalidOperation):
            return False, "every item unit_price must be zero or greater", None
        total += price * item["quantity"]
    return True, None, total


def lambda_handler(event, context):
    try:
        payload = json.loads(event.get("body") or "{}")
    except json.JSONDecodeError:
        return _response(400, {"message": "request body must be valid JSON"})

    valid, message, total = validate_order(payload)
    if not valid:
        return _response(400, {"message": message})

    order = {
        "order_id": str(uuid.uuid4()),
        "customer_id": payload["customer_id"].strip(),
        "items": payload["items"],
        "total": str(total),
        "created_at": datetime.now(UTC).isoformat(),
        "status": "RECEIVED",
    }
    sqs.send_message(QueueUrl=os.environ["ORDERS_QUEUE_URL"], MessageBody=json.dumps(order))
    eventbridge.put_events(Entries=[{
        "Source": "cloudorder.api",
        "DetailType": "OrderAccepted",
        "Detail": json.dumps({"order_id": order["order_id"], "customer_id": order["customer_id"]}),
        "EventBusName": os.environ["EVENT_BUS_NAME"],
    }])
    print(json.dumps({"event": "order_accepted", "order_id": order["order_id"]}))
    return _response(202, {"order_id": order["order_id"], "status": "RECEIVED"})
