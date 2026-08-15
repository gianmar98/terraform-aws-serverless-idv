"use client"

import {useState} from "react";
import {signUp, confirmSignUp, signIn} from "aws-amplify/auth";
import { cn } from "@/lib/utils"
import { Button } from "@/components/ui/button"
import { Card, CardContent } from "@/components/ui/card"
import {
  Field,
  FieldDescription,
  FieldGroup,
  FieldLabel,
} from "@/components/ui/field"
import { Input } from "@/components/ui/input"
import {Popover, PopoverContent, PopoverTrigger} from "@/components/ui/popover"
import {useRouter} from "next/navigation";

//"mode" is a state machine: which form are we showing?
type Mode = "login" | "signup" | "confirm"

// Sign up isn't wired yet, so only the Terraform-seeded users can get in. Without this the
// page is a locked door with no key next to it.
// Must match a pair in `seed_users` in infrastructure/envs/dev/terraform.tfvars — those users
// are created by aws_cognito_user.seed, and their passwords already sit in plaintext in
// Terraform state, so printing one here changes nothing about the blast radius. Rotate the
// seed password and this constant is the second place to change.
const DEMO_LOGIN = {
  email: "demo1@example.com",
  password: "DemoPass123",
};


export function LoginForm({
  className,
  ...props
}: React.ComponentProps<"div">) {
  const router = useRouter();

  // Picks which of the three forms renders. Only the login form is built, so this
  // never leaves "login" yet — see tutorial 3.7 for the other two.
  const [mode, setMode] = useState<Mode>("login");

  const [email, setEmail] = useState("");
  const [password, setPassword] = useState("");
  const [code, setCode] = useState("");   // confirm mode only

  const [error, setError] = useState<string | null>(null);
  const [busy, setBusy] = useState(false); // true while a Cognito call is in flight

  // Which demo row was just copied, so that one row can confirm itself for a moment.
  const [copiedField, setCopiedField] = useState<string | null>(null);

  // Same helper as SubmitPanel's demo popover, fallback included: the site is served from an
  // S3 website endpoint over HTTP, and navigator.clipboard doesn't exist outside a secure
  // context — without the else branch the button silently does nothing in production while
  // working fine under `bun dev`. Both copies go once CloudFront puts the site on HTTPS.
  async function copyField(field: string, value: string) {
    if (navigator.clipboard) {
      await navigator.clipboard.writeText(value);
    } else {
      const el = document.createElement("textarea");
      el.value = value;
      document.body.appendChild(el);
      el.select();
      document.execCommand("copy");
      el.remove();
    }
    setCopiedField(field);
    setTimeout(() => setCopiedField(null), 1200);
  }

  // All three handlers need the same busy/error bookkeeping around one Cognito call,
  // so it lives here once rather than being repeated in each of them.
  async function run(action:() => Promise<void>){ //actual work to do
    setError(null); // clear old error messages
    setBusy(true);  //show "loading" disables button
    try{
      await action(); // do the actual action
    }catch(e){ //save error message so it can be shown
      setError(e instanceof Error ? e.message: String(e));
    } finally {
      setBusy(false) // no matter what happened, turn off "loading" when done
    }
  }

  const handleLogin = () =>
      run(async () => {
        await signIn({username: email, password}); // <- real Cognito call
        router.push("/"); // page.tsx re-checks getCurrentUser() and renders SubmitPanel
      });

  // Creates the account. Cognito then emails a code that handleConfirm exchanges for a
  // confirmed user. Unreachable until a signup form renders.
  const handleSignup = () =>
      run(async () => {
        await signUp({
          username: email, //login with this
          password,
          options: {userAttributes: {email}}, // data attached to account (email, phone, name, etc...)
        })
      })

  // Second half of signup: trades the emailed code for a confirmed account.
  // Also unreachable until a confirm form renders.
  const handleConfirm = () =>
      run(async () => {
        await confirmSignUp({username: email, confirmationCode: code}); //Cognito confirmation code it emails after sign up
      });

  // Holds whichever handler matches the current mode, so the form below can just call
  // submit() without knowing which one it got.
  const submit = mode=== "login" ? handleLogin: mode === "signup" ? handleSignup : handleConfirm;

  return (
    <div className={cn("flex flex-col gap-6", className)} {...props}>
      <Card className="overflow-hidden border-line bg-surface p-0 shadow-sm">
        <CardContent className="grid p-0 md:grid-cols-2">
          <form className="p-6 md:p-8"
                onSubmit={(e) => {
                  e.preventDefault(); // stop browser default full page reload submit
                  submit();
                }}>
            <FieldGroup>
              <div className="flex flex-col items-center gap-1.5 text-center">
                <h1 className="text-[1.75rem] font-semibold leading-tight tracking-[-0.01em] text-ink">Welcome back</h1>
                <p className="text-balance text-sm text-ink/65">
                  Login to your Giancarlo License Simulation Inc account
                </p>
              </div>
              <Field>
                <FieldLabel htmlFor="email" className="text-ink/65">Email</FieldLabel>
                <Input
                  id="email"
                  type="email"
                  placeholder="you@example.com"
                  value={email}
                  onChange={(e) => setEmail(e.target.value)}
                  autoComplete="email"
                  required
                />
              </Field>
              <Field>
                {/* "Forgot your password?" was removed with the rest of the dead links:
                    Cognito's reset flow isn't wired up, so it was a link to nowhere. */}
                <FieldLabel htmlFor="password" className="text-ink/65">Password</FieldLabel>
                <Input
                  id="password"
                  type="password"
                  value={password}
                  onChange={(e)=> setPassword(e.target.value)}
                  autoComplete="current-password"
                  required
                />
              </Field>
              {error && (
                <p className="rounded-md border-l-2 border-fail bg-fail/[0.07] px-3 py-2 text-sm text-fail" role="alert">
                  {error}
                </p>
              )}
              <Field>
                <Button
                  type="submit"
                  disabled={busy}
                  className="h-11 w-full cursor-pointer bg-thread-strong font-medium text-white transition-colors duration-200 hover:bg-ink disabled:cursor-not-allowed disabled:opacity-45"
                >
                  {busy ? "Logging in..." : "Login"}
                </Button>
              </Field>
              {/* Sits under the primary CTA on purpose: it's the answer to a question the
                  reader has already asked ("...but I don't have an account"), and an outline
                  mono control doesn't compete with the one filled button on the screen.
                  Click-to-copy is the same gesture SubmitPanel's Demo data popover teaches. */}
              <Popover>
                <PopoverTrigger
                  // Explicit: inside a <form>, a button with no type submits it, so the
                  // trigger would fire an empty login and render an error under the popover.
                  type="button"
                  className={
                    "mx-auto cursor-pointer rounded-md border border-ink/50 px-3 py-1.5 font-mono " +
                    "text-[11px] uppercase tracking-[0.12em] text-ink/70 transition-colors duration-200 " +
                    "hover:border-ink/70 hover:text-ink"
                  }
                >
                  Get test credentials
                </PopoverTrigger>
                <PopoverContent align="center" className="w-80 bg-surface text-ink ring-ink/10">
                  <p className="font-mono text-[10px] uppercase tracking-[0.2em] text-ink/65">
                    Demo account
                  </p>
                  <p className="text-[13px] leading-5 text-ink/65">
                    Sign up isn&apos;t wired yet. Click a field to copy it.
                  </p>
                  {/* border-line is fine here (a decorative panel edge and row dividers) but
                      never on a control — it's 1.53:1 on paper and fails WCAG 1.4.11. The
                      trigger above uses border-ink/50 for exactly that reason. */}
                  <div className="flex flex-col overflow-hidden rounded-md border border-line">
                    {Object.entries(DEMO_LOGIN).map(([field, value]) => (
                      <button
                        key={field}
                        type="button"
                        onClick={() => copyField(field, value)}
                        aria-label={`Copy demo ${field}`} // visible text is the value, not the action
                        className={
                          "flex items-center justify-between gap-3 border-b border-line/70 px-2.5 py-1.5 " +
                          "text-left transition-colors duration-200 last:border-b-0 hover:bg-thread/[0.06]"
                        }
                      >
                        <span className="font-mono text-[10px] uppercase tracking-[0.12em] text-ink/65">
                          {field}
                        </span>
                        {/* Swapping the value for "copied" keeps the confirmation off colour
                            alone (WCAG 1.4.1) — a green tick would say it twice in one channel. */}
                        <span className="font-mono text-[12px] text-ink">
                          {copiedField === field ? "copied" : value}
                        </span>
                      </button>
                    ))}
                  </div>
                </PopoverContent>
              </Popover>
              {/* The Apple/Google/Meta buttons and their "Or continue with" separator that
                  ship with shadcn's login-04 block were removed: no federated IdPs are
                  configured in Cognito, so they were three controls that looked interactive
                  and did nothing. Dead affordances are the single loudest "unfinished" signal
                  on a sign-in screen. Re-add them if you ever wire federated sign-in. */}
              <FieldDescription className="text-center text-ink/65">
                Don&apos;t have an account? <a href="#" className="underline hover:text-ink">Sign up</a>
              </FieldDescription>
            </FieldGroup>
          </form>
          {/* Replaces shadcn's <img src="/next.svg"> demo panel. This is the brief's signature
              element: guilloché line-engraving on security ink, with the wordmark set in the
              same Plex Sans 700 / uppercase / wide-tracking as the app header. Decorative, so
              aria-hidden and hidden entirely below md rather than shrunk. */}
          <div aria-hidden className="relative hidden overflow-hidden bg-ink md:block">
            <div
              className="absolute inset-0 opacity-[0.14]"
              style={{
                backgroundImage:
                  "repeating-radial-gradient(circle at 50% 38%, var(--color-paper) 0 1px, transparent 1px 13px)," +
                  "repeating-radial-gradient(circle at 26% 72%, var(--color-thread) 0 1px, transparent 1px 17px)",
              }}
            />
            <div className="relative flex h-full flex-col justify-between p-8">
              <div className="flex items-center gap-2.5">
                <span className="h-4 w-1 rounded-full bg-thread" />
                <span className="text-[13px] font-bold uppercase tracking-[0.22em] text-paper">
                  Identity Verification
                </span>
              </div>
              <p className="font-mono text-[11px] uppercase leading-5 tracking-[0.18em] text-paper/55">
                Document check
                <br />
                Face match
                <br />
                Licence validation
              </p>
            </div>
          </div>
        </CardContent>
      </Card>
      {/* Replaces shadcn's Terms of Service / Privacy Policy line, which linked nowhere.
          Set in the same mono / uppercase / wide-tracked voice as the field keys. */}
      <p className="text-center font-mono text-[11px] uppercase tracking-[0.18em] text-ink/65">
        Built by Giancarlo Martinez · ACI Capstone 1
      </p>
    </div>
  )
}
