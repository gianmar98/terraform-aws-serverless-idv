# Copyright (c) 2026 Giancarlo Martinez
# SPDX-License-Identifier: MIT
"""Browser-facing API sitting behind the HTTP API's JWT authorizer.

Routes (HTTP API v2 payload format):
  POST /api/upload-url    -> {"uuid", "key", "url"}   presigned S3 PUT
  GET  /api/status/{uuid} -> {"status", ...flags}     DynamoDB GetItem

Unlike the pipeline handlers, this one RETURNS failures as JSON status codes
instead of raising. API Gateway turns an unhandled exception into a bare 502
with no body, which the browser cannot show the user anything useful about.
"""
import json
import os
import uuid

import boto3
from botocore.config import Config
from botocore.exceptions import ClientError

# One client per service, created once at import.
# signature_version is load-bearing: the default presigns with SigV2, and the bucket is
# SSE-KMS, which only accepts SigV4 - the browser's PUT fails with a 403 InvalidArgument
# ("Requests specifying Server Side Encryption with AWS KMS managed keys require AWS
# Signature Version 4"). Nothing here fails; only the browser's later upload does.
s3 = boto3.client('s3', config=Config(signature_version='s3v4'))
dynamodb = boto3.resource('dynamodb')
table = dynamodb.Table(os.environ['TABLE'])
bucket = os.environ['BUCKET']

# Written onto the item by the pipeline AFTER the row itself exists: WriteToDynamo creates
# the row, then CompareFaces, CompareDetails and SubmitLicense each set one of these. A row
# with only some of them present means the state machine is still running.
RESULT_FLAGS = ["LICENSE_SELFIE_MATCH", "LICENSE_DETAILS_MATCH", "LICENSE_VALIDATION"]

# 8 hex chars matches the app_uuid the pipeline already keys everything on (e.g. 8d247914).
UUID_LENGTH = 8
HEX_DIGITS = set("0123456789abcdef")

# Long enough for a browser to PUT a 20MB zip, short enough that a leaked URL dies fast.
PRESIGN_EXPIRY_SECONDS = 300


def _response(status_code, body):
    return {
        "statusCode": status_code,
        "headers": {"content-type": "application/json"},
        "body": json.dumps(body),
    }


def lambda_handler(event, context):
    "Routes on event['routeKey']. Both routes are already authenticated by the JWT authorizer."
    route = event.get('routeKey', '')
    print(json.dumps({"route": route}))

    try:
        if route == "POST /api/upload-url":
            app_uuid = uuid.uuid4().hex[:UUID_LENGTH]
            key = f"zipped/{app_uuid}.zip"
            # Signed locally against this role's credentials - no API call is made here, so
            # signing needs no permission. s3:PutObject + kms:GenerateDataKey are what the
            # BROWSER's request is evaluated against when it uses the URL.
            url = s3.generate_presigned_url(
                'put_object',
                Params={"Bucket": bucket, "Key": key},
                ExpiresIn=PRESIGN_EXPIRY_SECONDS,
            )
            return _response(200, {"uuid": app_uuid, "key": key, "url": url})

        if route.startswith("GET /api/status"):
            app_uuid = (event.get('pathParameters') or {}).get('uuid') or ''
            # Reject anything that is not one of our own ids before it reaches DynamoDB.
            # A key over 2048 bytes raises ValidationException, which would surface as a 502.
            if len(app_uuid) != UUID_LENGTH or not set(app_uuid) <= HEX_DIGITS:
                return _response(400, {"error": "invalid uuid"})

            # The resource API deserializes DynamoDB attribute values, so the flags come
            # back as plain bools rather than {"BOOL": true}.
            item = table.get_item(Key={"APP_UUID": app_uuid}).get('Item')

            # "pending" covers both no-row-yet and row-without-all-results. WriteToDynamo
            # creates the row long before the flags land, so keying "done" off the row's
            # existence would stop the browser polling on a half-finished run.
            #
            # A FALSE flag is terminal, though: compare_faces and compare_details both raise
            # on a mismatch, which fails the state machine, so the remaining flags will never
            # be written. Waiting for all three would leave the browser polling forever on
            # exactly the runs a user most needs an answer for.
            flags_present = item or {}
            if any(flags_present.get(flag) is False for flag in RESULT_FLAGS):
                return _response(200, {"status": "done", **{flag: flags_present.get(flag) for flag in RESULT_FLAGS}})

            if not item or not all(flag in item for flag in RESULT_FLAGS):
                return _response(200, {"status": "pending"})

            return _response(200, {"status": "done", **{flag: item.get(flag) for flag in RESULT_FLAGS}})

        return _response(404, {"error": f"no route for {route}"})

    except ClientError as error:
        # Raising would give API Gateway an unhandled exception and the browser a bare 502.
        # Log the cause for CloudWatch, return a body the frontend can actually render.
        print(f"AWS call failed on {route}: {error}")
        return _response(500, {"error": "internal error"})


#TEST COMMAND
# aws lambda invoke --function-name AppApiLambdaFunction-dev \
# --cli-binary-format raw-in-base64-out \
# --payload '{"routeKey": "POST /api/upload-url"}' response.json
#
# aws lambda invoke --function-name AppApiLambdaFunction-dev \
# --cli-binary-format raw-in-base64-out \
# --payload '{"routeKey": "GET /api/status/{uuid}", "pathParameters": {"uuid": "9c358026"}}' response.json