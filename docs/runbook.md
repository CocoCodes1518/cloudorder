# Operations runbook

## Alarm: DLQ messages available

1. Open the CloudWatch alarm and identify the affected environment.
2. Inspect the DLQ message body and Lambda logs using its order ID.
3. Fix the underlying data or application issue.
4. Redrive messages from the DLQ to the main orders queue.
5. Confirm the message is processed once and the alarm returns to `OK`.

## Alarm: processor errors

1. Check Lambda error logs and recent deployments.
2. Verify DynamoDB permissions and table availability.
3. Confirm the queue visibility timeout exceeds the Lambda timeout.
4. Roll back the application artifact if a recent deployment caused the issue.
