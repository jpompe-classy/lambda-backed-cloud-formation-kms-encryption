#!/bin/usr/env python

import boto3
import os

def lambda_handler(event, context):
    client = boto3.client('kms')
    decrypted = client.decrypt(
        CiphertextBlob=os.getenv("SecretParam").decode('base64')
    )

    print decrypted

    return decrypted['Plaintext']
