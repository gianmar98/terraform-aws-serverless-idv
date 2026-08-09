# Cognito Module

Provisions the user directory and browser app client that authenticate the Next.js
frontend. Every `/api/*` call the browser makes carries a Cognito-issued JWT, which
the HTTP API's JWT authorizer validates before any Lambda runs.

## Resources

- `aws_cognito_user_pool.license_validation_users` — the user directory. `username_attributes = ["email"]` (users log in with an email, not a separate username), `auto_verified_attributes = ["email"]` (Cognito emails a verification code on sign-up). Password policy: 8+ chars, upper + lower + number, symbols not required. Account recovery is `verified_email` only.
- `aws_cognito_user_pool_client.web` — the public SPA app client the browser talks to. See "App client settings" below for the security-relevant arguments.
- `aws_cognito_user.seed` — demo logins, one per entry in `var.seed_users`, so a known account survives a `destroy`/`apply` cycle. Uses `password` (permanent, user lands `CONFIRMED`) rather than `temporary_password`, which would leave them in `FORCE_CHANGE_PASSWORD` and make Amplify's `signIn` return a new-password challenge the frontend doesn't handle. `email_verified = "true"` is set explicitly because `auto_verified_attributes` only covers self-signup. `message_action = "SUPPRESS"` stops the invite email.

## Inputs

| Name | Type | Description |
|---|---|---|
| `cognito_user_pool_name` | `string` | Name of the user pool (env-suffixed by the caller) |
| `cognito_user_pool_client_name` | `string` | Name of the app client (env-suffixed by the caller) |
| `seed_users` | `map(string)` | Demo logins as `email => password`. `sensitive`, defaults to `{}`. Validated against the pool's own password policy so a weak value fails at `plan` rather than mid-`apply`. Set in `envs/dev/terraform.tfvars`; keep it `{}` in prod |

## Outputs

| Name | Description |
|---|---|
| `user_pool_id` | Pool ID — becomes the frontend's `NEXT_PUBLIC_USER_POOL_ID` |
| `user_pool_client_id` | App client ID — the frontend's `NEXT_PUBLIC_USER_POOL_CLIENT_ID`, and the **audience** the API Gateway JWT authorizer matches against the token's `aud` claim |
| `issuer` | `https://` + the pool endpoint — the **issuer** the JWT authorizer matches against the token's `iss` claim |
| `cognito_user_pool_name` | Pool name |
| `cognito_user_pool_client_name` | App client name |

## App client settings

| Setting | Value | Why |
|---|---|---|
| `generate_secret` | `false` | A browser cannot hide a secret — anything shipped in the JS bundle is readable in DevTools. Cognito's public-client model uses SRP instead. Amplify's browser SDK does not support client secrets at all; setting this to `true` breaks login. |
| `explicit_auth_flows` | `SRP` + `REFRESH` | Whitelist of permitted login methods. Cognito's other flows (notably `ALLOW_USER_PASSWORD_AUTH`) send the raw password to AWS. Restricting to these two means no weaker method is reachable even if a client tries. **Left unset, AWS applies its own defaults** — declare it. |
| `access_token_validity` / `id_token_validity` | 60 minutes | A stolen token expires within the hour. Matches the AWS default, declared so it cannot drift silently. |
| `refresh_token_validity` | 30 days | Amplify silently exchanges this for fresh 60-minute tokens, so users are not logged out hourly. |
| `token_validity_units` | min / min / days | **The three validity numbers are meaningless without this block** — it defines what unit each integer is in. |
| `prevent_user_existence_errors` | `ENABLED` | Off, a failed login distinguishes "wrong password" from "no such user", letting an attacker enumerate which emails are registered. On, both return the same generic error. Also covers password-reset and sign-up responses. |

## Notes

- **The `.tf` filename is `congnito.tf` and the env's module block is `module "congito"`** — both misspelled. Harmless (Terraform doesn't care), but renaming either now would change state addresses, so they are left as-is.
- **SRP (Secure Remote Password)** means the password never leaves the browser. The client and Cognito each compute over the password and compare results; Cognito stores only a verifier, never the password. A traffic capture or a Cognito-side breach yields nothing reusable.
- **Tokens live in `localStorage`, readable by any JavaScript on the page.** This is inherent to browser-based auth (Auth0, Firebase, and Clerk all share it), not a Cognito flaw, and it only matters if hostile code is already running on your page — a malicious npm dependency, or unescaped user input (XSS). The real fix is HttpOnly cookies, which need a server-side component this static-export architecture does not have. See `frontend_tutorial.md` §2.1 for the full write-up.
- **Hosted UI is deliberately not used.** The frontend ships its own login form (`frontend/components/login-form.tsx`), and Amplify performs the SRP handshake directly — no redirects, no tokens in URLs. Hosted UI with `code` + PKCE would be equally secure; it was rejected because it cannot match the frontend's design, not for security reasons. If Hosted UI is ever added, use `allowed_oauth_flows = ["code"]` — **never `"implicit"`**, which returns tokens in the URL fragment where they land in browser history.
- **Consumed by the API, not yet by the frontend.** `user_pool_client_id` and `issuer` feed the `cognito_jwt` authorizer in `modules/apiGateway/`. The frontend's `amplify-config.ts` still reads `NEXT_PUBLIC_*` env vars filled by hand — `envs/dev/outputs.tf` now exports `frontend_user_pool_id` / `frontend_user_pool_client_id` to generate them from, but nothing automates that yet.
- **`seed_users` passwords land in Terraform state in plaintext.** The provider marks `password` sensitive so it's redacted from `plan`, but state is not encrypted at the value level. Acceptable here (tfvars is gitignored, the state bucket is SSE-S3 + `encrypt = true`, and these are throwaway demo accounts); not acceptable for real users, who should self-sign-up so Terraform never sees their password.
- **`for_each` cannot take `var.seed_users` directly** — it's `sensitive`, and `for_each` keys become resource addresses that Terraform prints. Hence `nonsensitive(toset(keys(var.seed_users)))`, which unwraps only the emails; the password is looked up separately via `var.seed_users[each.key]` and keeps its sensitive mark.
- **`list-users` shows UUIDs, not emails, in the `Username` column.** With `username_attributes = ["email"]` Cognito generates the username and treats the email as a sign-in alias (stored as the `email` attribute). Users still log in with their email — query `Attributes[?Name=='email']` to see who's who.
- **Users created through the app are invisible to Terraform.** Only `aws_cognito_user.seed` entries are in state, so self-signups are never reported as drift and never deleted by an `apply`. Removing a line from `seed_users`, however, does destroy that user.
- Both names are env-suffixed by the caller (`LicenseValidationCognitoUserPool-dev`, `LicenseValidationCognitoClient-dev`) so dev and prod can coexist in one account.
- **Renaming the pool's Terraform resource address is a replace, not a move** — it destroys the pool and every user in it, and the new pool gets a different ID that the frontend and JWT authorizer must be re-pointed at. Use `terraform state mv` instead once the pool holds real users.