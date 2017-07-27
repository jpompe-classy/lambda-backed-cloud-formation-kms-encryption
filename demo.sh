#!/usr/bin/env bash
set -xe

# init values
S3_BUCKET="$(cat /dev/urandom | tr -dc 'a-z0-9-' | fold -w 63 | head -n 1)"
# create s3 bucket
aws s3api create-bucket --bucket $S3_BUCKET --region $AWS_DEFAULT_REGION --create-bucket-configuration LocationConstraint=$AWS_DEFAULT_REGION
# package
aws cloudformation package \
  --template-file cloudformation/lambda-backed-cloud-formation-kms-encryption.yaml \
  --s3-bucket $S3_BUCKET \
  --output-template-file cloudformation/lambda-backed-cloud-formation-kms-encryption-packaged.yaml
# generate random secret
ECRET="$(cat /dev/urandom | tr -dc 'a-zA-Z0-9' | fold -w 256 | head -n 1)"
# deploy
aws cloudformation deploy \
  --template-file cloudformation/lambda-backed-cloud-formation-kms-encryption-packaged.yaml \
  --stack-name $STACK_NAME \
  --capabilities CAPABILITY_IAM \
  --parameter-overrides SuperSecretThing=$ECRET
# invoke
aws lambda invoke \
  --function-name $(aws cloudformation describe-stacks \
    --stack-name $STACK_NAME \
    --query 'Stacks[0].Outputs[?OutputKey==`LambdaDecryptionFunctionName`].OutputValue' \
    --output text) /tmp/decrypted_secret.txt
# validate
# we need to serialize the env var to match the python lambda context
# TODO: rewrite in JAVA to allow different return value
if [[ "$(cat /tmp/decrypted_secret.txt)" == "\"$ECRET\"" ]]; then
  echo SUCCESS
  echo stored secret value was "\$echo \$ECRET: $ECRET"
  echo returned value is "$\(cat /tmp/decrypted_secret.txt\): $(cat /tmp/decrypted_secret.txt)"
else
  echo FAILURE
fi

# cleanup
aws s3 rm s3://$S3_BUCKET/ --recursive
aws s3api delete-bucket --bucket $S3_BUCKET
