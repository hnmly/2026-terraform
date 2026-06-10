resource "aws_cloudwatch_log_group" "ecs" {
  name              = "/ecs/skills-book-app"
  retention_in_days = 7
  tags              = { Name = "/ecs/skills-book-app" }
}

resource "aws_cloudwatch_log_metric_filter" "filter_4xx" {
  name           = "skills-book-4xx-filter"
  log_group_name = aws_cloudwatch_log_group.ecs.name
  pattern        = "{ $.status >= 400 && $.status < 500 }"

  metric_transformation {
    name      = "skills-book-4xx-count"
    namespace = "Skills/CloudComputing/Task1"
    value     = "1"
  }
}

resource "aws_cloudwatch_log_metric_filter" "filter_5xx" {
  name           = "skills-book-5xx-filter"
  log_group_name = aws_cloudwatch_log_group.ecs.name
  pattern        = "{ $.status >= 500 && $.status < 600 }"

  metric_transformation {
    name      = "skills-book-5xx-count"
    namespace = "Skills/CloudComputing/Task1"
    value     = "1"
  }
}

resource "aws_cloudwatch_metric_alarm" "alarm_4xx" {
  alarm_name          = "skills-book-4xx-alarm"
  comparison_operator = "GreaterThanOrEqualToThreshold"
  evaluation_periods  = 1
  metric_name         = "skills-book-4xx-count"
  namespace           = "Skills/CloudComputing/Task1"
  period              = 60
  statistic           = "Sum"
  threshold           = 1
  datapoints_to_alarm = 1
  treat_missing_data  = "notBreaching"
  alarm_description   = "4xx error count >= 1"
}

resource "aws_cloudwatch_metric_alarm" "alarm_5xx" {
  alarm_name          = "skills-book-5xx-alarm"
  comparison_operator = "GreaterThanOrEqualToThreshold"
  evaluation_periods  = 1
  metric_name         = "skills-book-5xx-count"
  namespace           = "Skills/CloudComputing/Task1"
  period              = 60
  statistic           = "Sum"
  threshold           = 1
  datapoints_to_alarm = 1
  treat_missing_data  = "notBreaching"
  alarm_description   = "5xx error count >= 1"
}
