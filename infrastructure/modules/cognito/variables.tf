variable "cognito_user_pool_name" {
  description = "This is the name of the authentication user pool from cognito"
  type        = string
}

variable "cognito_user_pool_client_name" {
  description = "This is the name of the authentication user pool from cognito"
  type        = string
}

#seed user passwords is redacted from output but is stored in plaintext in terraform.tfstate
#users that sign up through cognito UI they will not appear on tfstate file
#in prod, mark as "{}" the map variable
variable "seed_users" {
  description = "List of user(s) that will be added at creation"
  type        = map(string)

  sensitive = true
  default   = {}

  validation {
    condition     = alltrue([for email in keys(var.seed_users) : can(regex("^[^@\\s]+@[^@\\s]+\\.[^@\\s]+$", email))])
    error_message = "Every seed_users key must be an email address -> the pool uses username_attributes = [\"email\"]."
  }
  validation {
    # Must satisfy the pool's password_policy above, or apply fails with InvalidPasswordException.
    condition     = alltrue([for pw in values(var.seed_users) : length(pw) >= 8 && can(regex("[a-z]", pw)) && can(regex("[A-Z]", pw)) && can(regex("[0-9]", pw))])
    error_message = "Every seed_users password needs 8+ chars with an uppercase, a lowercase, and a number."
  }
}

