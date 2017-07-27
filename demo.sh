#!/usr/bin/env bash
set -xe

# init values
S3_BUCKET="$(cat /dev/urandom | LC_CTYPE=C tr -dc 'a-z0-9-' | fold -w 62 | head -n 1)"
# bucket name can't start with '-'
if [[ ${S3_BUCKET:0:1} == '-' ]]; then
  S3_BUCKET="1${S3_BUCKET[@]:1}"
fi
STACK_NAME=lambda-backed-cloud-formation-kms-encryption
# create s3 bucket
aws s3api create-bucket --bucket $S3_BUCKET --region $AWS_DEFAULT_REGION --create-bucket-configuration LocationConstraint=$AWS_DEFAULT_REGION
# package
aws cloudformation package \
  --template-file cloudformation/lambda-backed-cloud-formation-kms-encryption.yaml \
  --s3-bucket $S3_BUCKET \
  --output-template-file cloudformation/lambda-backed-cloud-formation-kms-encryption-packaged.yaml
# generate random secret
ECRET="$(cat /dev/urandom | LC_CTYPE=C tr -dc 'a-zA-Z0-9' | fold -w 256 | head -n 1)"
# deploy
aws cloudformation deploy \
  --template-file cloudformation/lambda-backed-cloud-formation-kms-encryption-packaged.yaml \
  --stack-name $STACK_NAME \
  --capabilities CAPABILITY_IAM \
  --parameter-overrides SuperSecretThingKey=SuperSecretThing SuperSecretThingValue=$ECRET
# invoke
aws lambda invoke \
  --function-name $(aws cloudformation describe-stacks \
    --stack-name $STACK_NAME \
    --query 'Stacks[0].Outputs[?OutputKey==`LambdaDecryptionFunctionName`].OutputValue' \
    --output text) /tmp/decrypted_secret.txt
# validate
# we need to serialize the env var to match the python lambda context
# TODO: rewrite in JAVA to allow different return value
if [[ "$(cat /tmp/decrypted_secret.txt)" == "\"{\\\"SuperSecretThingKey\\\": \\\"SuperSecretThing\\\", \\\"SuperSecretThingValue\\\": \\\"$ECRET\\\"}\"" ]]; then
  echo SUCCESS
  echo stored secret value was "\$echo \$ECRET: $ECRET"
  echo returned value is "$\(cat /tmp/decrypted_secret.txt\): $(cat /tmp/decrypted_secret.txt)"
  env ECRET=$ECRET python -c "import ast
import os
import json
with open('/tmp/decrypted_secret.txt', 'r') as infile:
    returned_data = ast.literal_eval(json.load(infile))
print returned_data['SuperSecretThingValue']
print os.getenv('ECRET')
secrets = {}
if os.getenv('ECRET') == returned_data['SuperSecretThingValue']:
    print 'SUCESSS'
    print 'stored secret value: {}'.format(os.getenv('ECRET'))
    print 'returned value: {}'.format(returned_data['SuperSecretThingValue'])
    print 'full response: {}'.format(returned_data)
    secrets[returned_data['SuperSecretThingKey']] = returned_data['SuperSecretThingValue']
    print json.dumps(secrets)
"
else
  echo FAILURE
fi

# cleanup
aws s3 rm s3://$S3_BUCKET/ --recursive
aws s3api delete-bucket --bucket $S3_BUCKET
rm /tmp/decrypted_secret.txt
