from decimal import Decimal

from src.ingest_order import validate_order


def test_valid_order_has_total():
    valid, message, total = validate_order({
        "customer_id": "customer-1",
        "items": [{"sku": "sku-1", "quantity": 2, "unit_price": "12.50"}],
    })
    assert valid is True
    assert message is None
    assert total == Decimal("25.00")


def test_rejects_empty_items():
    valid, message, total = validate_order({"customer_id": "customer-1", "items": []})
    assert valid is False
    assert message == "items must be a non-empty list"
    assert total is None


def test_rejects_non_finite_price():
    valid, message, total = validate_order({
        "customer_id": "customer-1",
        "items": [{"sku": "sku-1", "quantity": 1, "unit_price": "NaN"}],
    })
    assert valid is False
    assert message == "every item unit_price must be zero or greater"
    assert total is None
