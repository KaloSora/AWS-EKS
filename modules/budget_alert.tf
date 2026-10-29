module "budget_alert" {
  source             = "./budget_alert"
  budget_email       = var.budget_email
  budget_start       = var.budget_start
  budget_end         = var.budget_end
  budget_amount      = var.budget_amount
  budget_unit        = var.budget_unit
}
