terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 4.16"
    }
  }

  required_version = ">= 1.2.0"
}

provider "aws" {
  profile = "default"
  region  = "us-east-1"
}

# Create DynamoDB Table
resource "aws_dynamodb_table" "table" {
  name           = "GoogleSEO"
  billing_mode   = "PROVISIONED"
  read_capacity  = 20
  write_capacity = 20
  hash_key       = "UniqueID"
  range_key      = "SortID"
  attribute {
    name = "UniqueID"
    type = "S"
  }
  attribute {
    name = "SortID"
    type = "S"
  }
  tags = {
    "Environment" : "Development"
  }
}
# Create IAM Role for Lambda Function
resource "aws_iam_role" "iam_role" {
  name = "LambdaFunctionExecutionRole"
  assume_role_policy = jsonencode(
    {
      "Version" : "2012-10-17",
      "Statement" : [
        {
          "Action" : "sts:AssumeRole",
          "Principal" : {
            "Service" : "lambda.amazonaws.com"
          },
          "Effect" : "Allow"
        }
      ]
    }
  )
}

# Create IAM Policy to Access DynamoDB Table for Lambda
resource "aws_iam_policy" "iam_policy" {
  name = "DynamoDBLambdaPolicy"
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "dynamodb:*"
        ]
        Resource = [
          aws_dynamodb_table.table.arn
        ]
      }
    ]
  })
}

# Attach AWS Manage Policy for Lambda to Execute inside VPC
resource "aws_iam_role_policy_attachment" "iam_role_policy_attachment" {
  role       = aws_iam_role.iam_role.name
  policy_arn = aws_iam_policy.iam_policy.arn
}

# Create Zip File for Code
data "archive_file" "lambda_zip_file" {
  type        = "zip"
  source_file = "${path.module}/src/lambda_function.py"
  output_path = "${path.module}/lambda.zip"
}

# Create Lambda Function
resource "aws_lambda_function" "lambda_function" {
  function_name    = "getGoogleSEO"
  filename         = data.archive_file.lambda_zip_file.output_path
  source_code_hash = data.archive_file.lambda_zip_file.output_base64sha256
  handler          = "lambda_handler"
  role             = aws_iam_role.iam_role.arn
  runtime          = "python3.10"
  memory_size      = 512
  timeout          = 60
  environment {
    variables = {
      "APIUrl" : "https://www.google.com",
      "DynamoDBTableName" : aws_dynamodb_table.table.name
    }
  }
  tags = {
    "Environment" : "Development"
  }
}


resource "aws_cloudwatch_event_rule" "cloudwatch_event_rule" {
  name                = "cron_job_cloudwatch_rule_every_day"
  description         = "Cron Job which Trigger Lambda Function Every Day at 23:29"
  schedule_expression = "cron(59 23 * * ? *)"
  tags = {
    "Environment" : "Development"
  }
}

# Create CloudWatch Event Target
resource "aws_cloudwatch_event_target" "cloudwatch_event_target" {
  rule      = aws_cloudwatch_event_rule.cloudwatch_event_rule.id
  arn       = aws_lambda_function.lambda_function.arn
  target_id = "lambda"
}

# Create Lambda Permission to allow cloudwatch to call lambda function
resource "aws_lambda_permission" "lambda_permission" {
  statement_id  = "AllowExecutionFromCloudWatch"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.lambda_function.function_name
  principal     = "events.amazonaws.com"
  source_arn    = aws_cloudwatch_event_rule.cloudwatch_event_rule.arn
}

output "MyFunction" {
  value       = aws_lambda_function.lambda_function.arn
  description = "Lambda function name"
}
