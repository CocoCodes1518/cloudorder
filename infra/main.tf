locals {
  name = "${var.project_name}-${terraform.workspace}"
  tags = {
    Project     = "CloudOrder"
    ManagedBy   = "Terraform"
    Environment = terraform.workspace
  }
}

resource "aws_dynamodb_table" "orders" {
  name         = "${local.name}-orders"
  billing_mode = "PAY_PER_REQUEST"
  hash_key     = "order_id"
  attribute { name = "order_id" type = "S" }
  point_in_time_recovery { enabled = true }
  tags = local.tags
}

resource "aws_sqs_queue" "orders_dlq" {
  name                      = "${local.name}-orders-dlq"
  message_retention_seconds = 1209600
  tags                      = local.tags
}

resource "aws_sqs_queue" "orders" {
  name                       = "${local.name}-orders"
  visibility_timeout_seconds = 60
  redrive_policy = jsonencode({
    deadLetterTargetArn = aws_sqs_queue.orders_dlq.arn
    maxReceiveCount     = 3
  })
  tags = local.tags
}

resource "aws_cloudwatch_event_bus" "orders" {
  name = "${local.name}-events"
  tags = local.tags
}

data "aws_iam_policy_document" "lambda_assume" {
  statement {
    actions = ["sts:AssumeRole"]
    principals { type = "Service" identifiers = ["lambda.amazonaws.com"] }
  }
}

resource "aws_iam_role" "ingest" {
  name               = "${local.name}-ingest-role"
  assume_role_policy = data.aws_iam_policy_document.lambda_assume.json
  tags               = local.tags
}

resource "aws_iam_role" "processor" {
  name               = "${local.name}-processor-role"
  assume_role_policy = data.aws_iam_policy_document.lambda_assume.json
  tags               = local.tags
}

resource "aws_iam_role" "get_order" {
  name               = "${local.name}-get-order-role"
  assume_role_policy = data.aws_iam_policy_document.lambda_assume.json
  tags               = local.tags
}

data "aws_iam_policy_document" "ingest" {
  statement { actions = ["sqs:SendMessage"] resources = [aws_sqs_queue.orders.arn] }
  statement { actions = ["events:PutEvents"] resources = [aws_cloudwatch_event_bus.orders.arn] }
  statement { actions = ["logs:CreateLogGroup", "logs:CreateLogStream", "logs:PutLogEvents"] resources = ["*"] }
}

data "aws_iam_policy_document" "processor" {
  statement { actions = ["sqs:ReceiveMessage", "sqs:DeleteMessage", "sqs:GetQueueAttributes"] resources = [aws_sqs_queue.orders.arn] }
  statement { actions = ["dynamodb:PutItem"] resources = [aws_dynamodb_table.orders.arn] }
  statement { actions = ["events:PutEvents"] resources = [aws_cloudwatch_event_bus.orders.arn] }
  statement { actions = ["logs:CreateLogGroup", "logs:CreateLogStream", "logs:PutLogEvents"] resources = ["*"] }
}

data "aws_iam_policy_document" "get_order" {
  statement { actions = ["dynamodb:GetItem"] resources = [aws_dynamodb_table.orders.arn] }
  statement { actions = ["logs:CreateLogGroup", "logs:CreateLogStream", "logs:PutLogEvents"] resources = ["*"] }
}

resource "aws_iam_role_policy" "ingest" {
  name   = "${local.name}-ingest"
  role   = aws_iam_role.ingest.id
  policy = data.aws_iam_policy_document.ingest.json
}
resource "aws_iam_role_policy" "processor" {
  name   = "${local.name}-processor"
  role   = aws_iam_role.processor.id
  policy = data.aws_iam_policy_document.processor.json
}
resource "aws_iam_role_policy" "get_order" {
  name   = "${local.name}-get-order"
  role   = aws_iam_role.get_order.id
  policy = data.aws_iam_policy_document.get_order.json
}

data "archive_file" "ingest" {
  type        = "zip"
  source_dir  = "${path.module}/../src"
  output_path = "${path.module}/ingest.zip"
}
data "archive_file" "processor" {
  type        = "zip"
  source_dir  = "${path.module}/../src"
  output_path = "${path.module}/processor.zip"
}

resource "aws_lambda_function" "ingest" {
  function_name    = "${local.name}-ingest"
  role             = aws_iam_role.ingest.arn
  runtime          = "python3.12"
  handler          = "ingest_order.lambda_handler"
  filename         = data.archive_file.ingest.output_path
  source_code_hash = data.archive_file.ingest.output_base64sha256
  timeout          = 15
  environment { variables = { ORDERS_QUEUE_URL = aws_sqs_queue.orders.url, EVENT_BUS_NAME = aws_cloudwatch_event_bus.orders.name } }
  tags = local.tags
}

resource "aws_lambda_function" "processor" {
  function_name    = "${local.name}-processor"
  role             = aws_iam_role.processor.arn
  runtime          = "python3.12"
  handler          = "process_order.lambda_handler"
  filename         = data.archive_file.processor.output_path
  source_code_hash = data.archive_file.processor.output_base64sha256
  timeout          = 30
  environment { variables = { ORDERS_TABLE_NAME = aws_dynamodb_table.orders.name, EVENT_BUS_NAME = aws_cloudwatch_event_bus.orders.name } }
  tags = local.tags
}

resource "aws_lambda_function" "get_order" {
  function_name    = "${local.name}-get-order"
  role             = aws_iam_role.get_order.arn
  runtime          = "python3.12"
  handler          = "get_order.lambda_handler"
  filename         = data.archive_file.processor.output_path
  source_code_hash = data.archive_file.processor.output_base64sha256
  timeout          = 10
  environment { variables = { ORDERS_TABLE_NAME = aws_dynamodb_table.orders.name } }
  tags = local.tags
}

resource "aws_lambda_event_source_mapping" "orders" {
  event_source_arn = aws_sqs_queue.orders.arn
  function_name    = aws_lambda_function.processor.arn
  batch_size       = 10
}

resource "aws_apigatewayv2_api" "orders" {
  name          = "${local.name}-api"
  protocol_type = "HTTP"
  cors_configuration {
    allow_headers = ["content-type"]
    allow_methods = ["GET", "POST", "OPTIONS"]
    allow_origins = ["*"]
  }
  tags          = local.tags
}
resource "aws_apigatewayv2_integration" "ingest" {
  api_id                 = aws_apigatewayv2_api.orders.id
  integration_type       = "AWS_PROXY"
  integration_uri        = aws_lambda_function.ingest.invoke_arn
  payload_format_version = "2.0"
}
resource "aws_apigatewayv2_route" "create_order" {
  api_id    = aws_apigatewayv2_api.orders.id
  route_key = "POST /orders"
  target    = "integrations/${aws_apigatewayv2_integration.ingest.id}"
}
resource "aws_apigatewayv2_integration" "get_order" {
  api_id                 = aws_apigatewayv2_api.orders.id
  integration_type       = "AWS_PROXY"
  integration_uri        = aws_lambda_function.get_order.invoke_arn
  payload_format_version = "2.0"
}
resource "aws_apigatewayv2_route" "get_order" {
  api_id    = aws_apigatewayv2_api.orders.id
  route_key = "GET /orders/{order_id}"
  target    = "integrations/${aws_apigatewayv2_integration.get_order.id}"
}
resource "aws_apigatewayv2_stage" "default" {
  api_id      = aws_apigatewayv2_api.orders.id
  name        = "$default"
  auto_deploy = true
  default_route_settings { throttling_burst_limit = 50 throttling_rate_limit = 25 }
  tags = local.tags
}
resource "aws_lambda_permission" "api" {
  statement_id  = "AllowApiGatewayInvoke"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.ingest.function_name
  principal     = "apigateway.amazonaws.com"
  source_arn    = "${aws_apigatewayv2_api.orders.execution_arn}/*/*"
}
resource "aws_lambda_permission" "get_order_api" {
  statement_id  = "AllowApiGatewayGetOrder"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.get_order.function_name
  principal     = "apigateway.amazonaws.com"
  source_arn    = "${aws_apigatewayv2_api.orders.execution_arn}/*/*"
}

resource "aws_cloudwatch_metric_alarm" "dlq_messages" {
  alarm_name          = "${local.name}-dlq-messages"
  alarm_description   = "Orders require investigation in the dead-letter queue."
  namespace           = "AWS/SQS"
  metric_name         = "ApproximateNumberOfMessagesVisible"
  dimensions          = { QueueName = aws_sqs_queue.orders_dlq.name }
  statistic           = "Maximum"
  comparison_operator = "GreaterThanOrEqualToThreshold"
  threshold           = 1
  evaluation_periods  = 1
  period              = 300
  treat_missing_data  = "notBreaching"
}

# The dashboard is hosted privately in S3 and exposed through CloudFront over HTTPS.
resource "aws_s3_bucket" "web" {
  bucket_prefix = "${local.name}-web-"
  force_destroy = true
  tags          = local.tags
}
resource "aws_s3_bucket_public_access_block" "web" {
  bucket                  = aws_s3_bucket.web.id
  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}
resource "aws_s3_bucket_ownership_controls" "web" {
  bucket = aws_s3_bucket.web.id
  rule { object_ownership = "BucketOwnerEnforced" }
}
resource "aws_cloudfront_origin_access_control" "web" {
  name                              = "${local.name}-web-oac"
  description                       = "CloudOrder dashboard S3 access"
  origin_access_control_origin_type = "s3"
  signing_behavior                  = "always"
  signing_protocol                  = "sigv4"
}
data "aws_cloudfront_cache_policy" "managed_optimized" { name = "Managed-CachingOptimized" }
data "aws_cloudfront_cache_policy" "managed_disabled" { name = "Managed-CachingDisabled" }
resource "aws_cloudfront_distribution" "web" {
  enabled             = true
  default_root_object = "index.html"
  origin {
    domain_name              = aws_s3_bucket.web.bucket_regional_domain_name
    origin_id                = "cloudorder-web"
    origin_access_control_id = aws_cloudfront_origin_access_control.web.id
  }
  default_cache_behavior {
    allowed_methods        = ["GET", "HEAD", "OPTIONS"]
    cached_methods         = ["GET", "HEAD"]
    target_origin_id       = "cloudorder-web"
    viewer_protocol_policy = "redirect-to-https"
    cache_policy_id        = data.aws_cloudfront_cache_policy.managed_optimized.id
  }
  ordered_cache_behavior {
    path_pattern           = "config.js"
    allowed_methods        = ["GET", "HEAD", "OPTIONS"]
    cached_methods         = ["GET", "HEAD"]
    target_origin_id       = "cloudorder-web"
    viewer_protocol_policy = "redirect-to-https"
    cache_policy_id        = data.aws_cloudfront_cache_policy.managed_disabled.id
  }
  restrictions { geo_restriction { restriction_type = "none" } }
  viewer_certificate { cloudfront_default_certificate = true }
  tags = local.tags
}
data "aws_iam_policy_document" "web_bucket" {
  statement {
    principals { type = "Service" identifiers = ["cloudfront.amazonaws.com"] }
    actions   = ["s3:GetObject"]
    resources = ["${aws_s3_bucket.web.arn}/*"]
    condition { test = "StringEquals" variable = "AWS:SourceArn" values = [aws_cloudfront_distribution.web.arn] }
  }
}
resource "aws_s3_bucket_policy" "web" {
  bucket = aws_s3_bucket.web.id
  policy = data.aws_iam_policy_document.web_bucket.json
}
resource "aws_s3_object" "index" {
  bucket       = aws_s3_bucket.web.id
  key          = "index.html"
  source       = "${path.module}/../demo/index.html"
  etag         = filemd5("${path.module}/../demo/index.html")
  content_type = "text/html"
}
resource "aws_s3_object" "styles" {
  bucket       = aws_s3_bucket.web.id
  key          = "styles.css"
  source       = "${path.module}/../demo/styles.css"
  etag         = filemd5("${path.module}/../demo/styles.css")
  content_type = "text/css"
}
resource "aws_s3_object" "app" {
  bucket       = aws_s3_bucket.web.id
  key          = "app.js"
  source       = "${path.module}/../demo/app.js"
  etag         = filemd5("${path.module}/../demo/app.js")
  content_type = "application/javascript"
}
resource "aws_s3_object" "config" {
  bucket       = aws_s3_bucket.web.id
  key          = "config.js"
  content      = "window.CLOUDORDER_API_URL = '${aws_apigatewayv2_stage.default.invoke_url}';"
  content_type = "application/javascript"
}
