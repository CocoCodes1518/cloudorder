# Interview notes

## 30-second overview

CloudOrder receives an order through a REST endpoint, validates it, and puts it on SQS. A separate Lambda consumes the queue and stores the final record in DynamoDB. This decouples the user-facing API from downstream work and protects the system when traffic or processing time increases.

## Reliability decisions

- SQS retains work when the processor is temporarily unavailable.
- Failed messages move to a DLQ after three receives for investigation instead of disappearing.
- DynamoDB conditional writes make the consumer idempotent: replayed SQS messages do not create duplicates.
- Lambda retries transient failures; visibility timeout is longer than the function timeout.

## Security decisions

- Each Lambda role only has the actions and resources it needs.
- The API has request throttling; production would add authentication (Cognito or an authorizer).
- No secrets are stored in code or Terraform state.

## Good next enhancements

1. Add Cognito JWT authorization and per-customer access control.
2. Add a Step Functions payment/fulfilment workflow.
3. Ship logs and metrics to a dashboard, then alert on DLQ depth and error rate.
4. Add Terraform remote state with an S3 backend and DynamoDB state locking.
