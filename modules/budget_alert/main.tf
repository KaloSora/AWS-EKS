resource "aws_budgets_budget" "free_tier" {
  name         = "FreeTier-Total-200USD"
  budget_type  = "COST"
  limit_amount = var.budget_amount
  limit_unit   = var.budget_unit

  time_unit         = "CUSTOM"
  time_period_start = var.budget_start
  time_period_end   = var.budget_end

  cost_types {
    include_credit = false
    include_refund = false
    use_blended    = false
    use_amortized  = false
  }

  dynamic "notification" {
    for_each = toset([30, 50, 75, 90, 100])

    content {
      comparison_operator        = "GREATER_THAN"
      threshold                  = notification.value
      threshold_type             = "PERCENTAGE"
      notification_type          = "ACTUAL"
      subscriber_email_addresses = [var.budget_email]
    }
  }

  notification {
    comparison_operator        = "GREATER_THAN"
    threshold                  = 100
    threshold_type             = "PERCENTAGE"
    notification_type          = "FORECASTED"
    subscriber_email_addresses = [var.budget_email]
  }
}