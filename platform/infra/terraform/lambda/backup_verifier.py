import os
import zlib
from urllib.parse import unquote_plus

import boto3

s3 = boto3.client("s3")
cw = boto3.client("cloudwatch")
NAMESPACE = os.environ.get("METRIC_NAMESPACE", "DevopsApp/Backups")


def _verify(bucket: str, key: str) -> tuple[bool, int]:
    head = s3.head_object(Bucket=bucket, Key=key)
    size = head["ContentLength"]
    if size < 1024:
        return False, size
    body = s3.get_object(Bucket=bucket, Key=key, Range="bytes=0-65535")["Body"].read()
    try:
        text = zlib.decompressobj(16 + zlib.MAX_WBITS).decompress(body, 4096)
    except zlib.error:
        return False, size
    return b"PostgreSQL database dump" in text, size


def handler(event, context):
    for rec in event.get("Records", []):
        bucket = rec["s3"]["bucket"]["name"]
        key = unquote_plus(rec["s3"]["object"]["key"])
        ok, size = _verify(bucket, key)
        cw.put_metric_data(
            Namespace=NAMESPACE,
            MetricData=[
                {"MetricName": "BackupVerified", "Value": 1.0 if ok else 0.0, "Unit": "Count"},
                {"MetricName": "BackupSizeBytes", "Value": float(size), "Unit": "Bytes"},
            ],
        )
        print({"key": key, "verified": ok, "size": size})
    return {"status": "done"}
