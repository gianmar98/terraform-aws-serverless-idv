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
import {useRouter} from "next/navigation";
// TODO: import { useRouter } from "next/navigation";
//   Needed so a successful login can redirect to "/" (see tutorial 3.9 — page.tsx
//   redirects unauthenticated users to /login, so login needs the reverse redirect).
// TODO: import { signIn, signUp, confirmSignUp } from "aws-amplify/auth";
//   These are the three Cognito calls this form drives, one per Mode.

//"mode" is a state machine: which form are we showing?
type Mode = "login" | "signup" | "confirm"


export function LoginForm({
  className,
  ...props
}: React.ComponentProps<"div">) {
  // TODO: const router = useRouter();
  //   Router instance used only in handleLogin's success path.
  const router = useRouter();

  // TODO: const [mode, setMode] = useState<Mode>("login");
  //   Drives which of the three forms below renders. Right now this file only
  //   ever shows the login form — swapping mode is what makes "Sign up" work.
  const [mode, setMode] = useState<Mode>("login");

  // TODO: controlled-input state, one pair per field the active mode needs:
    const [email, setEmail] = useState("");
    const [password, setPassword] = useState("");
    const [code, setCode] = useState("");       // confirm mode only
  //   Inputs below are currently uncontrolled (no value/onChange) — nothing
  //   typed into them is readable in JS yet, so there's nothing to submit.

  // TODO: const [error, setError] = useState<string | null>(null);
  //   Surfaced under the submit button; mirrors the pattern in SubmitPanel.tsx.
  const [error, setError] = useState<string | null>(null);
  // TODO: const [busy, setBusy] = useState(false);
  //   Disables the submit button while an Amplify call is in flight.
  const [busy, setBusy] = useState(false);

  // TODO: async function run(fn: () => Promise<void>) { ... }
  //   Shared try/setBusy(true)/catch(setError)/finally(setBusy(false)) wrapper —
  //   handleLogin/handleSignUp/handleConfirm all repeat this, so wrap once
  //   instead of three times (see SubmitPanel.tsx's handleSubmit for the same shape).
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

  // TODO: Only needed once you add a "Sign up" form (mode === "signup"); the block
  //   for that form isn't in this file yet — see tutorial 3.7 for the shape.
  const handleSignup = () =>
      run(async () => {
        await signUp({
          username: email, //login with this
          password,
          options: {userAttributes: {email}}, // data attached to account (email, phone, name, etc...)
        })
      })

  // TODO: Same — only needed once a confirm-code form exists.
  const handleConfirm = () =>
      run(async () => {
        await confirmSignUp({username: email, confirmationCode: code}); //Cognito confirmation code it emails after sign up
      });

  // TODO: const submit = mode === "login" ? handleLogin : mode === "signup" ? handleSignUp : handleConfirm;
  //   `submit` is just a variable holding a reference to whichever handler
  //   function matches the current mode — a const CAN hold a function, and
  //   calling submit() below calls whatever function it currently points to.
  //   Needed because the form onSubmit below already calls submit(), but
  //   nothing defines it yet (that's the TS2552 "Cannot find name 'submit'" error).
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
                <div className="flex items-center">
                  <FieldLabel htmlFor="password" className="text-ink/65">Password</FieldLabel>
                  <a
                    href="#"
                    className="ml-auto text-sm text-ink/65 underline underline-offset-2 hover:text-ink"
                  >
                    Forgot your password?
                  </a>
                </div>
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
      <FieldDescription className="px-6 text-center text-ink/65">
        By clicking continue, you agree to our <a href="#" className="underline hover:text-ink">Terms of Service</a>{" "}
        and <a href="#" className="underline hover:text-ink">Privacy Policy</a>.
      </FieldDescription>
    </div>
  )
}
