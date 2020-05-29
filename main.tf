data "archive_file" "alert_handler_zip" {
  type        = "zip"
  source_dir  = "${path.module}/files/lambda/alert_handler"
  output_path = "lambda_alert_handler.zip"
}

resource "aws_iam_policy" "alert_handler_iam_policy" {
  name = "${terraform.workspace}_lambda_alert_handler_policy"

  policy = <<EOF
{
  "Version": "2012-10-17",
  "Statement": [ {
    "Effect": "Allow",
    "Action": "logs:CreateLogGroup",
    "Resource": "arn:aws:logs:*:*:*"
  }, {
    "Effect": "Allow",
    "Action": [
      "logs:CreateLogStream",
      "logs:PutLogEvents"
    ],
    "Resource": "arn:aws:logs:*:*:*:*"
  }, {
    "Effect": "Allow",
    "Action": "sns:Publish",
    "Resource": "arn:aws:sns:*:*:*"
  } ]
}
EOF
}

resource "aws_iam_role" "alert_handler_iam_role" {
  name = "${terraform.workspace}_lambda_alert_handler_role"

  assume_role_policy = <<EOF
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Principal": {
        "Service": "lambda.amazonaws.com"
      },
      "Action": "sts:AssumeRole"
    }
  ]
}
EOF
}

resource "aws_iam_role_policy_attachment" "alert_handler_iam_rolepolicy_attachment" {
  role       = "${aws_iam_role.alert_handler_iam_role.name}"
  policy_arn = "${aws_iam_policy.alert_handler_iam_policy.arn}"
}

resource "aws_lambda_function" "alert_handler_lambda" {
  filename         = "lambda_alert_handler.zip"
  source_code_hash = "${data.archive_file.alert_handler_zip.output_base64sha256}"
  function_name    = "${terraform.workspace}_alert_handler"
  role             = "${aws_iam_role.alert_handler_iam_role.arn}"
  description      = "An Amazon SNS trigger that sends CloudWatch alarm notifications to Slack."
  handler          = "index.handler"
  runtime          = "nodejs12.x"
  timeout          = 30

  environment {
    variables {
      SLACK_PATH         = "${var.alarms_slack_path}"
      SLACK_CHANNEL_NAME = "${var.alarms_slack_channel_name}"
      ACCOUNT            = "scos-${terraform.workspace}"
    }
  }
}

resource "aws_lambda_permission" "with_sns" {
  statement_id  = "AllowExecutionFromSNS"
  action        = "lambda:InvokeFunction"
  function_name = "${aws_lambda_function.alert_handler_lambda.function_name}"
  principal     = "sns.amazonaws.com"
  source_arn    = "${aws_sns_topic.alert_handler_sns_topic.arn}"
}

resource "aws_sns_topic" "alert_handler_sns_topic" {
  name = "lambda_alert_topic"
}

resource "aws_sns_topic_policy" "alert_handler_sns_topic_policy" {
  arn = "${aws_sns_topic.alert_handler_sns_topic.arn}"

  policy = "${data.aws_iam_policy_document.alert_handler.json}"
}

data "aws_caller_identity" "current" {}

data "aws_iam_policy_document" "alert_handler" {
  policy_id = "__default_policy_ID"

  statement {
    actions = [
      "SNS:Subscribe",
      "SNS:SetTopicAttributes",
      "SNS:RemovePermission",
      "SNS:Receive",
      "SNS:Publish",
      "SNS:ListSubscriptionsByTopic",
      "SNS:GetTopicAttributes",
      "SNS:DeleteTopic",
      "SNS:AddPermission",
    ]

    condition {
      test     = "StringEquals"
      variable = "AWS:SourceOwner"

      values = [
        "${data.aws_caller_identity.current.account_id}",
      ]
    }

    effect = "Allow"

    principals {
      type        = "AWS"
      identifiers = ["*"]
    }

    resources = [
      "${aws_sns_topic.alert_handler_sns_topic.arn}",
    ]

    sid = "__default_statement_ID"
  }

  statement {
    actions = [
      "SNS:Publish"
    ]

    effect = "Allow"

    principals {
      type        = "Service"
      identifiers = ["events.amazonaws.com"]
    }

    resources = [
      "${aws_sns_topic.alert_handler_sns_topic.arn}",
    ]

    sid = "allow_publish_from_cloudwatch_events"
  }
}

resource "aws_sns_topic_subscription" "user_updates_sqs_target" {
  topic_arn = "${aws_sns_topic.alert_handler_sns_topic.arn}"
  protocol  = "lambda"
  endpoint  = "${aws_lambda_function.alert_handler_lambda.arn}"
}

//---------EVENTS---------//

variable "alarms_slack_path" {
  description = "Path to the Slack channel"
}

variable "alarms_slack_channel_name" {
  description = "Name of the Slack channel"
}

output "alert_handler_sns_topic_arn" {
  value = "${aws_sns_topic.alert_handler_sns_topic.arn}"
}