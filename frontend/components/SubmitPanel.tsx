"use client";

import type {ReactNode} from "react";
import {useEffect, useRef, useState} from "react";
import {useRouter} from "next/navigation";
import {signOut} from "aws-amplify/auth";
import {LICENSE_FIELDS, type LicenseDetails, type StatusResponse} from "@/lib/types";
import { requestUploadUrl, uploadZip, fetchStatus} from "@/lib/api";
import {buildSubmissionZip} from "@/lib/zip";
import {DobPicker} from "@/components/DobPicker";
import MrzStrip from "@/components/MrzStrip";
import {Popover, PopoverContent, PopoverTrigger} from "@/components/ui/popover";

// No onSignOut prop: page.tsx renders <SubmitPanel/> with no props, and the only thing a
// parent would do on sign-out is the redirect below - one call site, so the handler lives
// here rather than as a callback threaded through props.

// Mirrors MAX_ZIP_BYTES in unzip_lambda.py — the archive is rejected server-side above this.
// ponytail: checked against the raw image bytes, not the built zip. PNG/JPEG barely deflate,
// so raw total >= zip size, and staying under 20MB also clears the 50MB uncompressed limit.
// This is UX only — the real guard is the Lambda; the presigned URL is the trust boundary.
const MAX_ZIP_BYTES = 20 * 1024 * 1024;
const mb = (b: number) => (b / 1024 / 1024).toFixed(1);

// ---- Presentation tokens -----------------------------------------------------------------
// Field keys are set in Plex Mono, uppercase, wide-tracked - the "machine-readable voice"
// from the 6.2 brief. It reads as a form key on an official document rather than a web label.
// ink/65 is the lightest tint of ink that still clears 4.5:1 on white (measured: 62% is the
// floor). Anything lighter looks refined in a mockup and fails WCAG AA in practice.
const fieldLabel = "mb-1.5 block font-mono text-[11px] uppercase tracking-[0.14em] text-ink/65";

// One input treatment reused by every text field so the grid stays visually even. h-10 keeps
// the 40px rhythm and clears the 44px-with-label touch target.
// border-ink/50, not border-line: `line` (#C9D2DD) is only 1.53:1 against white, which is fine
// for a decorative divider but fails WCAG 1.4.11 for a control boundary - and here the border
// is the only thing that identifies the field, since input and card are both white. 50% ink
// measures 3.1:1.
const fieldInput =
  "h-10 w-full rounded-md border border-ink/50 bg-surface px-3 text-[15px] text-ink " +
  "transition-colors duration-200 placeholder:text-ink/55 hover:border-ink/70 " +
  "focus:outline-none focus-visible:border-thread focus-visible:ring-2 focus-visible:ring-thread/30";

// Errors use the palette's own `fail` token, not Tailwind's stock red - the brief treats
// pass/review/fail as one functional traffic-light, and a stray red-700 breaks that set.
// The left rule makes the alert scannable without relying on colour alone (WCAG 1.4.1).
const alertBox =
  "mt-4 rounded-md border-l-2 border-fail bg-fail/[0.07] px-3 py-2 text-sm text-fail";

// Shared by the two header buttons (Demo data, Sign Out) so they read as one control pair.
const headerButton =
  "shrink-0 cursor-pointer rounded-md border border-line bg-surface px-3 py-1.5 text-sm " +
  "font-medium text-ink/70 transition-colors duration-200 hover:border-ink/25 hover:text-ink";

// Download links for the sample documents in public/. A plain anchor with `download` is the
// whole feature - no JS, and it still works from the static export behind CloudFront.
const downloadLink =
  "flex-1 rounded-md border border-ink/50 px-2.5 py-1.5 text-center font-mono text-[11px] " +
  "uppercase tracking-[0.12em] text-ink/70 transition-colors duration-200 hover:border-ink/70 hover:text-ink";

// Small caps rule that separates the form into scannable groups.
function SectionLabel({children}: {children: ReactNode}) {
  return (
    <div className="mb-3 flex items-center gap-3">
      <span className="font-mono text-[10px] uppercase tracking-[0.2em] text-ink/65">{children}</span>
      <span aria-hidden className="h-px flex-1 bg-line/70" />
    </div>
  );
}

// Mock data matching the sample licence in TestZipUpload/8d247914_license.png, so submitting
// the form as-is (with that licence + selfie) produces a PASS.
// Written in normal casing on purpose: the licence prints "NICK SAMPLE" in all-caps, and
// compare_details_lambda.py normalizes both sides (upper + date parsing) before comparing.
// If this ever stops matching, that normalizer is the thing that broke.
const MOCK: LicenseDetails = {
  FIRST_NAME: "Nick",
  LAST_NAME: "Sample",
  DOCUMENT_NUMBER: "S123456579010",
  DATE_OF_BIRTH: "1957-01-12", // DobPicker's yyyy-MM-dd; the licence prints 01/12/1957
  ADDRESS: "123 Main Street",
  STATE_IN_ADDRESS: "FL",
  CITY_IN_ADDRESS: "Tallahassee",
  ZIP_CODE_IN_ADDRESS: "000001234",
};

export default function SubmitPanel(){
  const router = useRouter();
  const [details, setDetails] = useState<LicenseDetails>(MOCK);
  const [license, setLicense] = useState<File | null>(null);
  const [selfie, setSelfie] = useState<File | null>(null);
  const [uuid, setUuid] = useState<string | null>(null);
  const [status, setStatus] = useState<StatusResponse | null>(null);
  const [error, setError] = useState<string |null>(null);
  const [busy, setBusy] = useState(false);
  // Which demo field was just copied, so that one row can confirm itself for a moment.
  const [copiedField, setCopiedField] = useState<string | null>(null);

  async function copyField(field: string, value: string) {
    await navigator.clipboard.writeText(value);
    setCopiedField(field);
    setTimeout(() => setCopiedField(null), 1200);
  }

  // holds timer's ID, without causing component to re-render when it changes
  //setInterval() start a timer that gives back ID so you can stop it later with clearInterval(id)
  //useRef(null) is empty box to store timer ID, survives across re renders
  const timer = useRef<ReturnType<typeof setInterval> | null>(null);

  //useEffect => "when to do something"
  // Poll GET /api/status while having a uuid and it is still pending
  useEffect(() => {
    if (!uuid) return; // no uuid? don't start polling (nothing uploaded yet)
    let attempts = 0;
    timer.current = setInterval(async () => { //every time timer fires, +1 attempt
      attempts += 1;
      try {
        const s = await fetchStatus(uuid); //ask backend status of uuid, save the answer so UI can see it
        setStatus(s);
        //Stop when done or give up after ~2 min. If not it polls forever
        // stop once is "done" or it tried for over 40 times
        if ((s.status === "done" || attempts >= 40) && timer.current){
          clearInterval(timer.current);
          if (s.status !== "done") //if stopped because it gave up, show error message
            setError("Still processing - check back later or contact support.");
        }
      }catch (e){ //show error of why it actually stopped
        setError(e instanceof Error ? e.message : String(e));
      }
    }, 3000); //return the polling function every 3,000ms (3 sec)
    return () => { //cleanup func
      if (timer.current) clearInterval(timer.current); //before setting up new timer, stop old timer first so it does not run in the background
    };
  }, [uuid]); //effect runs whenever uuid changes
  // uuid starts null, when user uploads file, app gets back real uuid and changes from null -> str.
  //  since the dependency changed, re runs the effect which kicks off the polling loop for that specific upload
  //  if it changed later, it will re run new polling loop

  //Total bytes of the two picked images ~= the zip we're about to PUT
  const totalBytes = (license?.size ?? 0) + (selfie?.size ?? 0);
  const tooBig = totalBytes > MAX_ZIP_BYTES;

  async function handleSubmit(){
    if (!license || !selfie){
      setError("Pick both a license image and a selfie.");
      return;
    }
    setError(null);
    setBusy(true);
    setStatus(null);
    try{
      //  export interface UploadUrlResponse {uuid: string;url: string;key: string;}
      const {uuid: id, url} = await requestUploadUrl();//1) presigned URL
      const zip = await buildSubmissionZip(id, details, license, selfie); //2) zip
      await uploadZip(url, zip) //3) PUT to S3 -> fires the pipeline
      setUuid(id); // 4) start polling (via the effect above)
    }catch (e) {
      setError(e instanceof Error ? e.message : String(e));
    } finally {
      setBusy(false);
    }
  }



  return(<>
    <div className={"mx-auto w-full max-w-2xl px-4 py-10 sm:py-14"}>
      <header className={"mb-6 flex items-end justify-between gap-4"}>
        <div>
          <h1 className={"text-[1.75rem] font-semibold leading-tight tracking-[-0.01em] text-ink"}>Submit your license</h1>
          <p className={"mt-1 text-sm text-ink/65"}>
            We compare your details and selfie against the document you upload.
          </p>
        </div>
        <div className={"flex shrink-0 items-center gap-2"}>
          {/* Everything a tester needs to try the happy path: the exact values the form is
              prefilled with (click a row to copy one back if you edit it), and the two sample
              documents they must upload. These are the real 8d247914 fixtures, so submitting
              them unchanged produces three PASS flags. */}
          <Popover>
            <PopoverTrigger className={headerButton}>Demo data</PopoverTrigger>
            <PopoverContent align={"end"} className={"w-80 bg-surface text-ink ring-ink/10"}>
              <p className={"font-mono text-[10px] uppercase tracking-[0.2em] text-ink/65"}>
                Demo test data
              </p>
              <p className={"text-[13px] leading-5 text-ink/65"}>
                Already filled in below. Click a field to copy it.
              </p>
              <div className={"flex flex-col overflow-hidden rounded-md border border-line"}>
                {Object.entries(MOCK).map(([field, value]) => (
                  <button
                    key={field}
                    type={"button"}
                    onClick={() => copyField(field, value)}
                    className={
                      "flex items-center justify-between gap-3 border-b border-line/70 px-2.5 py-1.5 " +
                      "text-left transition-colors duration-200 last:border-b-0 hover:bg-thread/[0.06]"
                    }
                  >
                    <span className={"font-mono text-[10px] uppercase tracking-[0.12em] text-ink/65"}>
                      {field.replaceAll("_", " ").toLowerCase()}
                    </span>
                    {/* Swapping the value for "copied" keeps the confirmation off colour alone
                        (WCAG 1.4.1) - a tick-plus-green would carry the same meaning twice. */}
                    <span className={"font-mono text-[12px] text-ink"}>
                      {copiedField === field ? "copied" : value}
                    </span>
                  </button>
                ))}
              </div>
              <div className={"flex gap-2"}>
                <a href={"/demo_license.png"} download={"demo_license.png"} className={downloadLink}>
                  Licence
                </a>
                <a href={"/demo_selfie.png"} download={"demo_selfie.png"} className={downloadLink}>
                  Selfie
                </a>
              </div>
            </PopoverContent>
          </Popover>
          <button
            // .finally, not .then: redirect even if signOut rejects, so the button is never a
            // silent no-op. Worst case the session survives and page.tsx's getCurrentUser()
            // gate catches it on the way back in.
            onClick={() => signOut().finally(() => router.push("/login"))}
            className={headerButton}
          >
            Sign Out
          </button>
        </div>

      </header>

      <div className={"rounded-xl border border-line bg-surface p-6 shadow-sm ring-1 ring-ink/[0.02]"}>
        <SectionLabel>Applicant details</SectionLabel>
        {/*Detail fields (filled with mock data)*/}
        <div className={"grid grid-cols-1 gap-x-4 gap-y-3 sm:grid-cols-2"}>
          {LICENSE_FIELDS.filter((field) => field !== "DATE_OF_BIRTH").map((field) => (
            <label key={field} className={"block"}>
              <span className={fieldLabel}>{field.replaceAll("_"," ").toLowerCase()}</span>
              <input
                placeholder={details[field]}
                onChange={(e) => setDetails({...details, [field]:e.target.value})}
                className={fieldInput}
              />
            </label>
        ))}

          <label className={"block"}>
            <span className={fieldLabel}>date of birth</span>
            <DobPicker
              value={details.DATE_OF_BIRTH}
              onChange={(v) => setDetails({...details, DATE_OF_BIRTH: v})}
            />
          </label>

        </div>

        {/*Image Pickers*/}
        <div className={"mt-7"}>
          <SectionLabel>Documents</SectionLabel>
          <div className={"grid grid-cols-1 gap-4 sm:grid-cols-2"}>
            <FilePick label={"License image"} onPick={setLicense} file={license}/>
            <FilePick label={"Selfie"} onPick={setSelfie} file={selfie}/>
          </div>
        </div>

        {
          tooBig && (
              <p className={alertBox} role="alert">
                Images total {mb(totalBytes)} MB — the limit is {mb(MAX_ZIP_BYTES)} MB. Pick smaller files.
              </p>
            )
        }

        {
          error && (
              <p className={alertBox} role="alert">{error}</p>
            )
        }

        <button
          onClick={handleSubmit}
          disabled={busy || tooBig}
          className={"mt-6 flex h-11 w-full cursor-pointer items-center justify-center rounded-md bg-thread-strong px-4 font-medium text-white transition-colors duration-200 hover:bg-ink focus:outline-none focus-visible:ring-2 focus-visible:ring-thread focus-visible:ring-offset-2 focus-visible:ring-offset-surface disabled:cursor-not-allowed disabled:opacity-45 disabled:hover:bg-thread-strong"}
        >
          {busy ? "Uploading...": `Submit for verification`}
        </button>
      </div>

      {/*Results*/}
      {uuid && (
          <div className={"mt-6 rounded-xl border border-line bg-surface p-6 shadow-sm"}>
            <div className={"mb-4 flex items-center justify-between gap-4 border-b border-line/70 pb-3"}>
              <h2 className={"text-lg font-semibold text-ink"}>Result</h2>
              <span className={"tabular font-mono text-xs text-ink/65"}>id: {uuid}</span>
            </div>

            {!status || status.status == "pending" ? (
                <div className={"flex items-center gap-2.5 py-1"} role="status" aria-live="polite">
                  <span aria-hidden className={"h-1.5 w-1.5 rounded-full bg-thread motion-safe:animate-pulse"} />
                  <p className={"text-sm text-ink/65"}>Processing — checking every 3 seconds.</p>
                </div>
            ):
                (
                    <div>
                      {/* divide-y gives the verdicts a ledger rhythm instead of floating rows */}
                      <div className={"divide-y divide-line/60"}>
                        <Flag label={"Face match (selfie vs license)"} value={status.LICENSE_SELFIE_MATCH}></Flag>
                        <Flag label={"Details match (form vs license)"} value={status.LICENSE_DETAILS_MATCH}></Flag>
                        <Flag label={"License validated"} value={status.LICENSE_VALIDATION}></Flag>
                      </div>
                      <MrzStrip id={uuid} name={`${details.FIRST_NAME} ${details.LAST_NAME}`} />
                    </div>
                )}
          </div>
      )}

      {/*<DobPicker*/}
      {/*  value={details.DATE_OF_BIRTH}*/}
      {/*  onChange={(v) => setDetails({...details, DATE_OF_BIRTH: v})}*/}
      {/*/>*/}
    </div>

  </>);
}

function FilePick({label, file, onPick}: {label:string; file: File | null; onPick: (f:File) => void;}){
    // Empty and filled are visually distinct states: dashed + muted while waiting, solid with a
    // teal check once a file is attached. Colour alone never carries the meaning - the border
    // style and the tick both change (WCAG 1.4.1).
    return(
        <label className={
          "group flex min-h-[104px] cursor-pointer flex-col items-center justify-center gap-1 rounded-md border-2 p-4 text-center transition-colors duration-200 " +
          "focus-within:ring-2 focus-within:ring-thread/40 focus-within:ring-offset-2 focus-within:ring-offset-surface " +
          (file
            ? "border-solid border-thread/40 bg-thread/[0.04]"
            : "border-dashed border-line hover:border-ink/30 hover:bg-ink/[0.02]")
        }>
          <span className={"flex items-center gap-1.5 text-sm font-medium text-ink/80"}>
            {file && (
              <svg aria-hidden viewBox="0 0 16 16" className="h-3.5 w-3.5 text-thread" fill="none" stroke="currentColor" strokeWidth="2.25" strokeLinecap="round" strokeLinejoin="round">
                <path d="M3 8.5 6.5 12 13 4.5" />
              </svg>
            )}
            {label}
          </span>
          <span className={"line-clamp-1 max-w-full break-all text-xs " + (file ? "text-ink/65" : "text-ink/65")}>
            {file ? file.name : `Click to choose`}
          </span>
          <input
            type={"file"}
            accept={"image/*"}
            className={"sr-only"}
            onChange={(e) => e.target.files?.[0] && onPick(e.target.files[0])}
          />
        </label>
    )
}


// '?' prop might be ommited if parent didn't pass it.
// false = check ran and it failed
function Flag({label, value}:{label:string, value?: boolean | string | null}){ //matches LICENSE_SELFIE_MATCH?: boolean | string | null
  //false === true => false
  const passed = value === true || value ==="true"; //if there was a result, was it good news?

  //false === true || false === false ... => true
  const hasResult = value === true || value === false || value === "true" || value ==="false"; // should I even look at pass/fail? Is there an answer at all?


  // The verdict pill is an inspection stamp: mono, uppercase, wide-tracked, ringed rather than
  // filled, so PASS and FAIL read as stamped marks and not as generic status chips.
  const color = !hasResult ?
      "bg-ink/[0.04] text-ink/65 ring-ink/20" //if no result
      : passed ? // if there is result
       "bg-pass/10 text-pass ring-pass/25" //and it passed = true => green
      :  "bg-fail/10 text-fail ring-fail/25"; // if there is a result and it did not pass, result existed but failed -> red
  const text = !hasResult ? "pending": passed? "PASS":"FAIL"; //if there is no resultColor = pending, else if passed is Pass and if not fail
  return(
    <div className="flex items-center justify-between gap-4 py-2.5">
      <span className="text-sm text-ink/80">{label}</span>
      <span className={`shrink-0 rounded-full px-2.5 py-1 font-mono text-[10px] font-semibold uppercase tracking-[0.14em] ring-1 ring-inset ${color}`}>{text}</span>
    </div>
  );
}