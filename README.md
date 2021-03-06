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
This demo assumes you have AWS credentials setup and you must set
the $AWS_DEFAULT_REGION env var. Most of the resources created are cleaned
up but but leaves up the CFN stack.
```bash
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
```

##### Sample Demo Output
```bash
env AWS_DEFAULT_REGION=us-west-2 ./demo.sh
++ cat /dev/urandom
++ LC_CTYPE=C
++ tr -dc a-z0-9-
++ fold -w 62
++ head -n 1
+ S3_BUCKET=3k2dm5evbj32hlffkmbrun2mkf0z7wxh7vdrit8yidpkv65iw10y5zu68kj38q
+ [[ 3 == \- ]]
+ STACK_NAME=lambda-backed-cloud-formation-kms-encryption
+ aws s3api create-bucket --bucket 3k2dm5evbj32hlffkmbrun2mkf0z7wxh7vdrit8yidpkv65iw10y5zu68kj38q --region us-west-2 --create-bucket-configuration LocationConstraint=us-west-2
{
    "Location": "http://3k2dm5evbj32hlffkmbrun2mkf0z7wxh7vdrit8yidpkv65iw10y5zu68kj38q.s3.amazonaws.com/"
}
+ aws cloudformation package --template-file cloudformation/lambda-backed-cloud-formation-kms-encryption.yaml --s3-bucket 3k2dm5evbj32hlffkmbrun2mkf0z7wxh7vdrit8yidpkv65iw10y5zu68kj38q --output-template-file cloudformation/lambda-backed-cloud-formation-kms-encryption-packaged.yaml
Uploading to 8fdd52a226d4d15923897a52a0720e19  320 / 320.0  (100.00%)%)
Successfully packaged artifacts and wrote output template to file cloudformation/lambda-backed-cloud-formation-kms-encryption-packaged.yaml.
Execute the following command to deploy the packaged template
aws cloudformation deploy --template-file /Users/jpompe/Scratch/lambda-backed-cloud-formation-kms-encryption/cloudformation/lambda-backed-cloud-formation-kms-encryption-packaged.yaml --stack-name <YOUR STACK NAME>
++ cat /dev/urandom
++ LC_CTYPE=C
++ tr -dc a-zA-Z0-9
++ fold -w 256
++ head -n 1
+ ECRET=nvEUfJLFv3dgn9JT08UMuETNIbZcwjGwehEfLVLnPtO2n4sZ9FQuI8M6TiLi5NgF6cvTNGtuzfbKu6JONaueRuZF9KHhYgLUxVRRVXLpDY5AkQq5qRrCyctvd5zTJVEsgaFlimkGkShKkUCi27Mo3pWYdKDRQol5KQtDpMUSYkqMUHskNW1LwSjKUMmBCrpzDYWcQwYMWIxROF8JFO0d9FhvosxUbK03YPFFq7wLs2SbFsnMvyG3tMe64ON2EuXh
+ aws cloudformation deploy --template-file cloudformation/lambda-backed-cloud-formation-kms-encryption-packaged.yaml --stack-name lambda-backed-cloud-formation-kms-encryption --capabilities CAPABILITY_IAM --parameter-overrides SuperSecretThingKey=SuperSecretThing SuperSecretThingValue=nvEUfJLFv3dgn9JT08UMuETNIbZcwjGwehEfLVLnPtO2n4sZ9FQuI8M6TiLi5NgF6cvTNGtuzfbKu6JONaueRuZF9KHhYgLUxVRRVXLpDY5AkQq5qRrCyctvd5zTJVEsgaFlimkGkShKkUCi27Mo3pWYdKDRQol5KQtDpMUSYkqMUHskNW1LwSjKUMmBCrpzDYWcQwYMWIxROF8JFO0d9FhvosxUbK03YPFFq7wLs2SbFsnMvyG3tMe64ON2EuXh
Waiting for changeset to be created..
Waiting for stack create/update to complete
Successfully created/updated stack - lambda-backed-cloud-formation-kms-encryption
++ aws cloudformation describe-stacks --stack-name lambda-backed-cloud-formation-kms-encryption --query 'Stacks[0].Outputs[?OutputKey==`LambdaDecryptionFunctionName`].OutputValue' --output text
+ aws lambda invoke --function-name lambda-backed-cloud-forma-LambdaDecryptionResource-5OVKPFASQB1S /tmp/decrypted_secret.txt
{
    "StatusCode": 200
}
++ cat /tmp/decrypted_secret.txt
+ [[ "{\"SuperSecretThingKey\": \"SuperSecretThing\", \"SuperSecretThingValue\": \"nvEUfJLFv3dgn9JT08UMuETNIbZcwjGwehEfLVLnPtO2n4sZ9FQuI8M6TiLi5NgF6cvTNGtuzfbKu6JONaueRuZF9KHhYgLUxVRRVXLpDY5AkQq5qRrCyctvd5zTJVEsgaFlimkGkShKkUCi27Mo3pWYdKDRQol5KQtDpMUSYkqMUHskNW1LwSjKUMmBCrpzDYWcQwYMWIxROF8JFO0d9FhvosxUbK03YPFFq7wLs2SbFsnMvyG3tMe64ON2EuXh\"}" == \"\{\\\"\S\u\p\e\r\S\e\c\r\e\t\T\h\i\n\g\K\e\y\\\"\:\ \\\"\S\u\p\e\r\S\e\c\r\e\t\T\h\i\n\g\\\"\,\ \\\"\S\u\p\e\r\S\e\c\r\e\t\T\h\i\n\g\V\a\l\u\e\\\"\:\ \\\"\n\v\E\U\f\J\L\F\v\3\d\g\n\9\J\T\0\8\U\M\u\E\T\N\I\b\Z\c\w\j\G\w\e\h\E\f\L\V\L\n\P\t\O\2\n\4\s\Z\9\F\Q\u\I\8\M\6\T\i\L\i\5\N\g\F\6\c\v\T\N\G\t\u\z\f\b\K\u\6\J\O\N\a\u\e\R\u\Z\F\9\K\H\h\Y\g\L\U\x\V\R\R\V\X\L\p\D\Y\5\A\k\Q\q\5\q\R\r\C\y\c\t\v\d\5\z\T\J\V\E\s\g\a\F\l\i\m\k\G\k\S\h\K\k\U\C\i\2\7\M\o\3\p\W\Y\d\K\D\R\Q\o\l\5\K\Q\t\D\p\M\U\S\Y\k\q\M\U\H\s\k\N\W\1\L\w\S\j\K\U\M\m\B\C\r\p\z\D\Y\W\c\Q\w\Y\M\W\I\x\R\O\F\8\J\F\O\0\d\9\F\h\v\o\s\x\U\b\K\0\3\Y\P\F\F\q\7\w\L\s\2\S\b\F\s\n\M\v\y\G\3\t\M\e\6\4\O\N\2\E\u\X\h\\\"\}\" ]]
+ echo SUCCESS
SUCCESS
+ echo stored secret value was '$echo $ECRET: nvEUfJLFv3dgn9JT08UMuETNIbZcwjGwehEfLVLnPtO2n4sZ9FQuI8M6TiLi5NgF6cvTNGtuzfbKu6JONaueRuZF9KHhYgLUxVRRVXLpDY5AkQq5qRrCyctvd5zTJVEsgaFlimkGkShKkUCi27Mo3pWYdKDRQol5KQtDpMUSYkqMUHskNW1LwSjKUMmBCrpzDYWcQwYMWIxROF8JFO0d9FhvosxUbK03YPFFq7wLs2SbFsnMvyG3tMe64ON2EuXh'
stored secret value was $echo $ECRET: nvEUfJLFv3dgn9JT08UMuETNIbZcwjGwehEfLVLnPtO2n4sZ9FQuI8M6TiLi5NgF6cvTNGtuzfbKu6JONaueRuZF9KHhYgLUxVRRVXLpDY5AkQq5qRrCyctvd5zTJVEsgaFlimkGkShKkUCi27Mo3pWYdKDRQol5KQtDpMUSYkqMUHskNW1LwSjKUMmBCrpzDYWcQwYMWIxROF8JFO0d9FhvosxUbK03YPFFq7wLs2SbFsnMvyG3tMe64ON2EuXh
++ cat /tmp/decrypted_secret.txt
+ echo returned value is '$\(cat /tmp/decrypted_secret.txt\): "{\"SuperSecretThingKey\": \"SuperSecretThing\", \"SuperSecretThingValue\": \"nvEUfJLFv3dgn9JT08UMuETNIbZcwjGwehEfLVLnPtO2n4sZ9FQuI8M6TiLi5NgF6cvTNGtuzfbKu6JONaueRuZF9KHhYgLUxVRRVXLpDY5AkQq5qRrCyctvd5zTJVEsgaFlimkGkShKkUCi27Mo3pWYdKDRQol5KQtDpMUSYkqMUHskNW1LwSjKUMmBCrpzDYWcQwYMWIxROF8JFO0d9FhvosxUbK03YPFFq7wLs2SbFsnMvyG3tMe64ON2EuXh\"}"'
returned value is $\(cat /tmp/decrypted_secret.txt\): "{\"SuperSecretThingKey\": \"SuperSecretThing\", \"SuperSecretThingValue\": \"nvEUfJLFv3dgn9JT08UMuETNIbZcwjGwehEfLVLnPtO2n4sZ9FQuI8M6TiLi5NgF6cvTNGtuzfbKu6JONaueRuZF9KHhYgLUxVRRVXLpDY5AkQq5qRrCyctvd5zTJVEsgaFlimkGkShKkUCi27Mo3pWYdKDRQol5KQtDpMUSYkqMUHskNW1LwSjKUMmBCrpzDYWcQwYMWIxROF8JFO0d9FhvosxUbK03YPFFq7wLs2SbFsnMvyG3tMe64ON2EuXh\"}"
+ env ECRET=nvEUfJLFv3dgn9JT08UMuETNIbZcwjGwehEfLVLnPtO2n4sZ9FQuI8M6TiLi5NgF6cvTNGtuzfbKu6JONaueRuZF9KHhYgLUxVRRVXLpDY5AkQq5qRrCyctvd5zTJVEsgaFlimkGkShKkUCi27Mo3pWYdKDRQol5KQtDpMUSYkqMUHskNW1LwSjKUMmBCrpzDYWcQwYMWIxROF8JFO0d9FhvosxUbK03YPFFq7wLs2SbFsnMvyG3tMe64ON2EuXh python -c 'import ast
import os
import json
with open('\''/tmp/decrypted_secret.txt'\'', '\''r'\'') as infile:
    returned_data = ast.literal_eval(json.load(infile))
print returned_data['\''SuperSecretThingValue'\'']
print os.getenv('\''ECRET'\'')
secrets = {}
if os.getenv('\''ECRET'\'') == returned_data['\''SuperSecretThingValue'\'']:
    print '\''SUCESSS'\''
    print '\''stored secret value: {}'\''.format(os.getenv('\''ECRET'\''))
    print '\''returned value: {}'\''.format(returned_data['\''SuperSecretThingValue'\''])
    print '\''full response: {}'\''.format(returned_data)
    secrets[returned_data['\''SuperSecretThingKey'\'']] = returned_data['\''SuperSecretThingValue'\'']
    print json.dumps(secrets)
'
nvEUfJLFv3dgn9JT08UMuETNIbZcwjGwehEfLVLnPtO2n4sZ9FQuI8M6TiLi5NgF6cvTNGtuzfbKu6JONaueRuZF9KHhYgLUxVRRVXLpDY5AkQq5qRrCyctvd5zTJVEsgaFlimkGkShKkUCi27Mo3pWYdKDRQol5KQtDpMUSYkqMUHskNW1LwSjKUMmBCrpzDYWcQwYMWIxROF8JFO0d9FhvosxUbK03YPFFq7wLs2SbFsnMvyG3tMe64ON2EuXh
nvEUfJLFv3dgn9JT08UMuETNIbZcwjGwehEfLVLnPtO2n4sZ9FQuI8M6TiLi5NgF6cvTNGtuzfbKu6JONaueRuZF9KHhYgLUxVRRVXLpDY5AkQq5qRrCyctvd5zTJVEsgaFlimkGkShKkUCi27Mo3pWYdKDRQol5KQtDpMUSYkqMUHskNW1LwSjKUMmBCrpzDYWcQwYMWIxROF8JFO0d9FhvosxUbK03YPFFq7wLs2SbFsnMvyG3tMe64ON2EuXh
SUCESSS
stored secret value: nvEUfJLFv3dgn9JT08UMuETNIbZcwjGwehEfLVLnPtO2n4sZ9FQuI8M6TiLi5NgF6cvTNGtuzfbKu6JONaueRuZF9KHhYgLUxVRRVXLpDY5AkQq5qRrCyctvd5zTJVEsgaFlimkGkShKkUCi27Mo3pWYdKDRQol5KQtDpMUSYkqMUHskNW1LwSjKUMmBCrpzDYWcQwYMWIxROF8JFO0d9FhvosxUbK03YPFFq7wLs2SbFsnMvyG3tMe64ON2EuXh
returned value: nvEUfJLFv3dgn9JT08UMuETNIbZcwjGwehEfLVLnPtO2n4sZ9FQuI8M6TiLi5NgF6cvTNGtuzfbKu6JONaueRuZF9KHhYgLUxVRRVXLpDY5AkQq5qRrCyctvd5zTJVEsgaFlimkGkShKkUCi27Mo3pWYdKDRQol5KQtDpMUSYkqMUHskNW1LwSjKUMmBCrpzDYWcQwYMWIxROF8JFO0d9FhvosxUbK03YPFFq7wLs2SbFsnMvyG3tMe64ON2EuXh
full response: {'SuperSecretThingKey': 'SuperSecretThing', 'SuperSecretThingValue': 'nvEUfJLFv3dgn9JT08UMuETNIbZcwjGwehEfLVLnPtO2n4sZ9FQuI8M6TiLi5NgF6cvTNGtuzfbKu6JONaueRuZF9KHhYgLUxVRRVXLpDY5AkQq5qRrCyctvd5zTJVEsgaFlimkGkShKkUCi27Mo3pWYdKDRQol5KQtDpMUSYkqMUHskNW1LwSjKUMmBCrpzDYWcQwYMWIxROF8JFO0d9FhvosxUbK03YPFFq7wLs2SbFsnMvyG3tMe64ON2EuXh'}
{"SuperSecretThing": "nvEUfJLFv3dgn9JT08UMuETNIbZcwjGwehEfLVLnPtO2n4sZ9FQuI8M6TiLi5NgF6cvTNGtuzfbKu6JONaueRuZF9KHhYgLUxVRRVXLpDY5AkQq5qRrCyctvd5zTJVEsgaFlimkGkShKkUCi27Mo3pWYdKDRQol5KQtDpMUSYkqMUHskNW1LwSjKUMmBCrpzDYWcQwYMWIxROF8JFO0d9FhvosxUbK03YPFFq7wLs2SbFsnMvyG3tMe64ON2EuXh"}
+ aws s3 rm s3://3k2dm5evbj32hlffkmbrun2mkf0z7wxh7vdrit8yidpkv65iw10y5zu68kj38q/ --recursive
delete: s3://3k2dm5evbj32hlffkmbrun2mkf0z7wxh7vdrit8yidpkv65iw10y5zu68kj38q/8fdd52a226d4d15923897a52a0720e19
delete: s3://3k2dm5evbj32hlffkmbrun2mkf0z7wxh7vdrit8yidpkv65iw10y5zu68kj38q/faa7689521c9ea18cf79ed76322d804c
+ aws s3api delete-bucket --bucket 3k2dm5evbj32hlffkmbrun2mkf0z7wxh7vdrit8yidpkv65iw10y5zu68kj38q
+ rm /tmp/decrypted_secret.txt
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
