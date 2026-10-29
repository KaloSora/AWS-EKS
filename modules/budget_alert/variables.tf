variable "budget_email" {
  description = "budget alert email address"
  type        = string
}

variable "budget_start" {
  description = "budget start time, UTC, format YYYY-MM-DD_HH:mm"
  type        = string
}

variable "budget_end" {
  description = "budget end time, UTC, format YYYY-MM-DD_HH:mm"
  type        = string
}

variable "budget_amount" {
  description = "budget amount"
  type        = number
}

variable "budget_unit" {
  description = "budget unit"
  type        = string
}