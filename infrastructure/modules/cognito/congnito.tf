
#Main directory that manages, stores, and authenticates actual users
resource "aws_cognito_user_pool" "license_validation_users" {
  name                     = var.cognito_user_pool_name
  username_attributes      = ["email"]
  auto_verified_attributes = ["email"]

  password_policy {
    minimum_length    = 8
    require_lowercase = true
    require_uppercase = true
    require_numbers   = true
    require_symbols   = false
  }

  account_recovery_setting {
    recovery_mechanism {
      name     = "verified_email"
      priority = 1
    }
  }

  # lifecycle {
  #   prevent_destroy = true
  # }
}

# app-specific gateway configuration that allows specific app to communicate with user dir
resource "aws_cognito_user_pool_client" "web" {
  name         = var.cognito_user_pool_client_name
  user_pool_id = aws_cognito_user_pool.license_validation_users.id

  #Prevent cognito from issuing a secret since the browser can't hide a secret
  generate_secret = false

  #Whitelisted login methods
  #ALLOW_USER_PASSWORD_AUTH -> login via SRP/Secure Remote Password (browser knows password without sending it)
  #                           password never leaves your machine, cognito never stores it, only a verifier. Without
  #                           it real password is sent to AWS (safe in TLS) but exists somewhere its not supposed to
  #ALLOW_REFRESH_TOKEN_AUTH -> lets 30-day refresh token mint new 60 min tokens so users are not logged out hourly.
  #                            when short 60 min token expires, amplify hands refresh token to Cognito and gets new short one backk
  #                            User notices no change, if token is ever stolen is useless in an hour
  explicit_auth_flows = [
    "ALLOW_USER_SRP_AUTH",
    "ALLOW_REFRESH_TOKEN_AUTH",
  ]
  #How long between 5 min -> 1 day which token will not be valid anymore
  #Token your API checks lives 60 units
  access_token_validity = 60
  #How long between 5 min -> 1 day which the ID token will not be valid anymore
  #Token holding user info (emails, sub) lives 60 units
  id_token_validity = 60
  #The token that renews the other 2 lives 30 units
  refresh_token_validity = 30

  #Access + ID expire in 1 hr (so if token is stolen dies fast) / refresh in 30 days (so users are not bothered)
  token_validity_units {
    access_token  = "minutes"
    id_token      = "minutes"
    refresh_token = "days"
  }

  # DO NOT show whether an email exists, give generic message so an attacher cannot gain any information from login
  prevent_user_existence_errors = "ENABLED"
}

resource "aws_cognito_user" "seed" {
  # Makes one user per email in seed_users. Terraform names each user after its email and
  # prints that name, so it can't be secret - nonsensitive() pulls out only the emails.
  # The passwords never pass through it, so they stay hidden.
  for_each = nonsensitive(toset(keys(var.seed_users))) //"keys" are just the email addresses


  user_pool_id = aws_cognito_user_pool.license_validation_users.id //which pool to put the users in
  username     = each.key                                          //the pool sets username_attributes = ["email"], so username IS the email
  password     = var.seed_users[each.key]                          //still secret - read straight from the map

  attributes = {
    email = each.key
    //users we create here start unverified, so say it out loud (has to be the string "true")
    email_verified = "true"
  }

  #Don't email an invite, password is already known
  message_action = "SUPPRESS"
}