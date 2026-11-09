# Monthly cost guardrail: emails at 80% of the limit (actual spend) and when the month
# is forecast to exceed it. Budgets are free; this project normally costs $0.

variable "budget_limit_usd" {
  description = "Monthly AWS budget in USD"
  type        = string
  default     = "5"
}

variable "budget_alert_email" {
  description = "Email for budget alerts. Empty = no budget created."
  type        = string
  default     = ""
}

resource "aws_budgets_budget" "monthly" {
  count        = var.budget_alert_email == "" ? 0 : 1
  name         = "fdic-pipeline-monthly"
  budget_type  = "COST"
  limit_amount = var.budget_limit_usd
  limit_unit   = "USD"
  time_unit    = "MONTHLY"

  notification {
    comparison_operator        = "GREATER_THAN"
    threshold                  = 80
    threshold_type             = "PERCENTAGE"
    notification_type          = "ACTUAL"
    subscriber_email_addresses = [var.budget_alert_email]
  }

  notification {
    comparison_operator        = "GREATER_THAN"
    threshold                  = 100
    threshold_type             = "PERCENTAGE"
    notification_type          = "FORECASTED"
    subscriber_email_addresses = [var.budget_alert_email]
  }
}
