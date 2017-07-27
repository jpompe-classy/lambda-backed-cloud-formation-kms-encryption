## CFN Update

This fork puts together the previous custom CFN Encryption resource,
with the AWS SAM, to allow "NoEcho" parameters to be passed to CFN templates
that are stored as encrypted environment variables in the lambda functions
that have decrypt permissions.

https://github.com/awslabs/serverless-application-model/blob/master/versions/2016-10-31.md

### Package

(note: you need an $S3_BUCKET to store the SAM template and source code)
```shell
aws cloudformation package \
  --template-file cloudformation/lambda-backed-cloud-formation-kms-encryption.yaml \
  --s3-bucket $S3_BUCKET \
  --output-template-file cloudformation/lambda-backed-cloud-formation-kms-encryption-packaged.yaml
```

### Deploy
(note: name the $STACK_NAME whatever you like, update $ECRET to validate)
```shell
aws cloudformation deploy \
  --template-file cloudformation/lambda-backed-cloud-formation-kms-encryption-packaged.yaml \
  --stack-name $STACK_NAME \
  --capabilities CAPABILITY_IAM \
  --parameter-overrides SuperSecretThing=$ECRET
```
### Validate
invoke the test lambda function and it will print your secret in the response
```shell
aws lambda invoke \
  --function-name $(aws cloudformation describe-stacks \
    --stack-name $STACK_NAME \
    --query 'Stacks[0].Outputs[?OutputKey==`LambdaDecryptionFunctionName`].OutputValue' \
    --output text) /tmp/decrypted_secret.txt --output text
)
cat /tmp/decrypted_secret.txt
"$ECRET"
```

#### DEMO
assumes you have AWS credentials setup, will create resources!
```bash
# init values
S3_BUCKET="$(cat /dev/urandom | tr -dc 'a-z0-9-' | fold -w 63 | head -n 1)"
AWS_DEFAULT_REGION=us-west-2
AWS_PROFILE=jpompe
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
```

## Using AWS KMS to Encrypt Values in CloudFormation Stacks

This repository contains an AWS Lambda-backed custom resource for AWS
CloudFormation. The custom resource will encrypt values using AWS Key
Management Service (KMS) and make the ecrypted version available to the
template.

The included example CloudFormation template
(lambda-backed-cloud-formation-kms-encryption.template) demonstrates the
usage of the custom resource.

For additional information, please read the in-depth article on
implementing this custom resource at
[https://ben.fogbutter.com/2016/02/22/using-kms-to-encrypt-cloud-formation-values.html]
(https://ben.fogbutter.com/2016/02/22/using-kms-to-encrypt-cloud-formation-values.html)

### Syntax

```json
{
    "Type": "AWS::CloudFormation::CustomResource",
    "Version": "1.0",
    "Properties": {
      "ServiceToken": String,
      "KeyId": String,
      "PlainText": String
    }
  }
}
```

### Properties

#### ServiceToken
The ARN of the AWS Lambda function backing the custom resource.

#### PlainText
The plain text value that should be encrypted.

#### KeyId
The key ID of the AWS KMS key that should be used to encrypt the value
provided in PlainText. Note that the Lambda function backing this
custom resource must have encrypt permissions for the specified key.


### Return Values

#### Ref

When you provide the custom resource's logical name to the Ref intrinsic
function, a GUID will be returned. This value has no meaning whatsoever,
and is only supplied because CloudFormation requires a value.

For more information about using the Ref function, see [Ref]
(http://docs.aws.amazon.com/AWSCloudFormation/latest/UserGuide/intrinsic-function-reference-ref.html).

#### Fn::GetAtt

Fn::GetAtt returns a value for a specified attribute of this type. This
section lists the available attributes and sample return values.

- **CipherText**: The Base64 encoded, encrypted format of the value that
                  was supplied for the PlainText property.

For more information about using Fn::GetAtt, see [Fn::GetAtt]
(http://docs.aws.amazon.com/AWSCloudFormation/latest/UserGuide/intrinsic-function-reference-getatt.html).
