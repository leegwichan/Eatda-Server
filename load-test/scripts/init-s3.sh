#!/bin/bash

# Wait for LocalStack to be ready
echo "Waiting for LocalStack to be ready..."
sleep 5

# Create S3 bucket
echo "Creating S3 bucket: eatda-storage-local"
awslocal s3 mb s3://eatda-storage-local

# Set bucket policy for public read (for testing)
echo "Setting bucket permissions..."
awslocal s3api put-bucket-acl --bucket eatda-storage-local --acl public-read

# List buckets to verify
echo "Verifying bucket creation..."
awslocal s3 ls

echo "LocalStack S3 initialization completed successfully"
