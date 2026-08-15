import boto3
import os
import csv
from datetime import datetime

#S3
s3 = boto3.client('s3')
unzipped_s3_prefix = "unzipped/"

#DynamoDB
dynamodb = boto3.resource('dynamodb')
table = dynamodb.Table(os.environ['TABLE'])# add ENV variable TABLE

#SNS
sns = boto3.client('sns')
env_topic = os.environ['TOPIC']# add ENV variable TABLE

#TEXTRACT
textract = boto3.client('textract')

def textract_response(bucket, license_key):
    "Extract the required identity fields from the license via Textract"
    print("Starting textract validation")

    response = textract.analyze_id(DocumentPages=[
        {
            'S3Object': {
                'Bucket': bucket,
                'Name': license_key,
            }
        }
    ])

    id_data = response['IdentityDocuments'][0]['IdentityDocumentFields']

    id_fields = {}  # added: return a dict instead of a positional tuple. The old tuple dropped DOCUMENT_NUMBER and STATE, and a tuple can't be compared field-by-field against the CSV. A dict keyed by field name is what compare_dictionaries() needs.
    for field in id_data:
        field_type = field['Type']['Text']
        if field_type in REQUIRED_FIELDS:                       # added: keep only the fields we care about, ignore everything else Textract returns.
            id_fields[field_type] = field['ValueDetection']['Text']

    return id_fields

# The two sides of the comparison are written by different authors: the CSV is typed by a
# human (or a web form), the other side is Textract reading the printed licence. They agree
# on the facts and disagree on the formatting - a licence prints "NICK" and "01/12/1957"
# where a form submits "Nick" and "1957-01-12". Comparing raw strings rejects a correct
# applicant, so normalize both sides before comparing.
DATE_FIELDS = {'DATE_OF_BIRTH'}
DATE_FORMATS = ('%Y-%m-%d', '%m/%d/%Y')  # form order, then licence order


def normalize(field, value):
    "Reduce a field to a form that survives case, padding, and date-format differences."
    text = (value or '').strip().upper()

    if field in DATE_FIELDS:
        for date_format in DATE_FORMATS:
            try:
                return datetime.strptime(text, date_format).strftime('%Y-%m-%d')
            except ValueError:
                continue
        # Unparseable: fall through and compare as text, so a garbage date still fails
        # rather than silently matching another garbage date.

    return text


def compare_dictionaries(app_uuid, details_dict, textract_dict):
    "Compare the CSV-supplied details against the Textract-extracted license fields"
    # added: this whole function was missing. Extracting license text is pointless unless we verify it matches what the customer submitted in the CSV.
    csv_subset = {k: normalize(k, details_dict.get(k, '')) for k in REQUIRED_FIELDS}       # added: narrow both sides to the same key set so the equality check is apples-to-apples (the CSV may carry extra columns).
    textract_subset = {k: normalize(k, textract_dict.get(k, '')) for k in REQUIRED_FIELDS} # added: .get(..., '') avoids a KeyError when Textract fails to read a field.
    comparison = csv_subset == textract_subset                              # added: dict equality compares every required field at once.

    if not comparison:  # name the fields that differ - a bare False is undebuggable in CloudWatch
        print('Detail mismatch:', {k: (csv_subset[k], textract_subset[k])
                                   for k in REQUIRED_FIELDS if csv_subset[k] != textract_subset[k]})

    table.update_item(                                                       # added: persist the result so downstream consumers can read LICENSE_DETAILS_MATCH, mirroring how compare_faces records LICENSE_SELFIE_MATCH.
        Key={'APP_UUID': app_uuid},
        UpdateExpression='SET LICENSE_DETAILS_MATCH = :d_match',
        ExpressionAttributeValues={':d_match': comparison}
    )

    if not comparison:                                                       # added: alert on mismatch, same pattern as the face-comparison failure notification.
        sns.publish(
            TopicArn=env_topic,
            Message='Data validation between the license and the .csv file FAILED',
            Subject='Data validation between the license and the .csv file FAILED',
        )
        raise ValueError('Data validation between the license and the .csv file FAILED')  # added: stop the pipeline on mismatch, mirroring compare_faces_lambda.

    return comparison

REQUIRED_FIELDS = [
    'DOCUMENT_NUMBER', 'FIRST_NAME', 'LAST_NAME', 'DATE_OF_BIRTH',
    'ADDRESS', 'STATE_IN_ADDRESS', 'CITY_IN_ADDRESS', 'ZIP_CODE_IN_ADDRESS'
]


def lambda_handler(event, context):
    print(f"Received event=> {event}")
    bucket = event['detail']['bucket']['name']
    app_uuid = event['application']['app_uuid']
    details_key = f"{unzipped_s3_prefix}{app_uuid}_details.csv"
    details_file = f"/tmp/{app_uuid}_details.csv"
    license_key = f"{unzipped_s3_prefix}{app_uuid}_license.png"

    s3.download_file(Bucket = bucket,
                     Key = details_key,
                     Filename =details_file)

    with open(details_file, 'r', encoding="utf-8") as file:
        reader = csv.DictReader(file)
        details_dict = next(reader)

    # Extract the license fields and verify they match the submitted CSV.
    textract_dict = textract_response(bucket, license_key)  # added: now returns a dict of license fields...
    compare_dictionaries(app_uuid, details_dict,textract_dict)  # added: ...which we compare against the CSV and record as LICENSE_DETAILS_MATCH. This is the validation step that was previously missing entirely.

    return True