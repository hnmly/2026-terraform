import json
import os

import boto3

dynamodb = boto3.resource("dynamodb")
TABLE_NAME = os.environ.get("TABLE_NAME", "wsc-table")


def _resp(status, body):
    return {
        "statusCode": status,
        "headers": {"Content-Type": "application/json"},
        "body": json.dumps(body, ensure_ascii=False),
    }


def lambda_handler(event, context):
    # ALB / CloudFront 통합: query string에서 client_id 추출
    params = (event or {}).get("queryStringParameters") or {}
    client_id = params.get("client_id")

    # 직접 호출 등 다른 형태 대비
    if not client_id and isinstance(event, dict):
        client_id = (event.get("client_id")
                     or (event.get("pathParameters") or {}).get("client_id"))

    if not client_id:
        return _resp(400, {"msg": "client_id is required"})

    table = dynamodb.Table(TABLE_NAME)
    result = table.get_item(Key={"client_id": client_id})
    item = result.get("Item")

    if not item:
        return _resp(404, {"msg": "Item not found"})

    return _resp(200, {
        "username": item.get("username"),
        "booking_id": item.get("booking_id"),
        "email": item.get("email"),
        "client_id": item.get("client_id"),
        "concert_name": item.get("concert_name"),
    })
