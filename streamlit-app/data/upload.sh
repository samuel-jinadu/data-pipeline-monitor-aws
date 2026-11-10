#!/bin/bash
# Load environment variables
ENV_FILE=${1:-../../environments/fakecloud.env}
source "$ENV_FILE"

aws s3 cp customers.parquet s3://data-warehouse-raw/customers.parquet
aws s3 cp orders.parquet s3://data-warehouse-raw/orders.parquet