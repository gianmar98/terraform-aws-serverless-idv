"use client";

import type {ReactNode} from "react";
import {useEffect, useMemo, useRef, useState} from "react";
import {useRouter} from "next/navigation";
import {signOut} from "aws-amplify/auth";
import {LICENSE_FIELDS, type LicenseDetails, type LicenseField, type StatusResponse} from "@/lib/types";
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

// LICENSE_FIELDS are SCREAMING_SNAKE (they're CSV column names); this is how they read to a
// human. Used by the field labels, the test-case rows, and the missing-fields error, so the
// three never drift apart.
const pretty = (field: string) => field.replaceAll("_", " ").toLowerCase();

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

// Shared by the two header buttons (Test cases, Sign Out) so they read as one control pair.
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

// Mock data matching the sample licence in TestZipUpload/8d247914_license.png. Two jobs: it's
// the placeholder text in every field (a hint at the shape of the answer, never submitted),
// and it's test case 1's payload below.
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

// The form starts genuinely empty so MOCK shows through as grey placeholder hints. A value
// only enters state when the user types it or loads a test case - so what reads as ink on the
// screen is exactly what gets written to the CSV, and a hint can never be submitted by accident.
const EMPTY = Object.fromEntries(LICENSE_FIELDS.map((f) => [f, ""])) as LicenseDetails;

// The three fixtures in TestZipUpload/, as one-click scenarios. All three carry the SAME
// licence image (public/demo_license.png, printed NICK SAMPLE / S123456579010 / 01-12-1957),
// so the only things that vary are the CSV and which selfie goes with it - which is exactly
// what makes them a clean set: one variable moves per case.
// `wrong` lists the fields that disagree with the printed licence, so the popover can mark
// them instead of making the reader diff two documents by eye.
type Scenario = {
  id: string;
  tab: string;
  expect: string;
  blurb: string;
  details: LicenseDetails;
  selfie: string;
  wrong: LicenseField[];
};

const SCENARIOS: Scenario[] = [
  {
    id: "8d247914",
    tab: "1 · Clean",
    expect: "Expect: all three pass",
    blurb: "Details match the printed licence and the selfie is the same face. These are also the values the empty form hints at as placeholders.",
    details: MOCK,
    selfie: "/demo_selfie.png",
    wrong: [],
  },
  {
    id: "9c358026",
    tab: "2 · Face",
    expect: "Expect: selfie fail",
    blurb: "Identical details, but the selfie is a different person. CompareFaces raises on a non-match, which fails the state machine - so the other two flags may never be written at all.",
    details: MOCK,
    selfie: "/demo_selfie_other.png",
    wrong: [],
  },
  {
    id: "7a135804",
    tab: "3 · Details",
    expect: "Expect: details fail",
    blurb: "Right face, wrong paperwork: the surname reads John where the licence prints Sample, and the ZIP has lost its leading zeros. The date is written 1/12/1957 in this fixture and still passes - the comparison parses dates rather than string-matching them.",
    details: {...MOCK, LAST_NAME: "John", ZIP_CODE_IN_ADDRESS: "1234"},
    selfie: "/demo_selfie.png",
    wrong: ["LAST_NAME", "ZIP_CODE_IN_ADDRESS"],
  },
];

export default function SubmitPanel(){
  const router = useRouter();
  const [details, setDetails] = useState<LicenseDetails>(EMPTY);
  const [license, setLicense] = useState<File | null>(null);
  const [selfie, setSelfie] = useState<File | null>(null);
  const [uuid, setUuid] = useState<string | null>(null);
  const [status, setStatus] = useState<StatusResponse | null>(null);
  const [error, setError] = useState<string |null>(null);
  const [busy, setBusy] = useState(false);
  // Which demo field was just copied, so that one row can confirm itself for a moment.
  const [copiedField, setCopiedField] = useState<string | null>(null);
  const [scenarioId, setScenarioId] = useState(SCENARIOS[0].id);
  const [loadingCase, setLoadingCase] = useState(false);
  // Controlled so loading a case can close the popover - the filled form behind it is the
  // confirmation, and leaving the panel open on top of it hides the thing that just changed.
  const [casesOpen, setCasesOpen] = useState(false);
  const scenario = SCENARIOS.find((s) => s.id === scenarioId) ?? SCENARIOS[0];

  // The fixtures ship in public/, so this is a same-origin fetch of a static file - it works
  // under `bun dev` and from the S3 website endpoint alike. buildSubmissionZip renames both
  // files to <uuid>_license.png / <uuid>_selfie.png, so the name given here is cosmetic.
  async function fileFrom(path: string) {
    const res = await fetch(path);
    // Without this a 404 still resolves: res.blob() happily wraps the error page, and the zip
    // ships an HTML document named *.png. The upload succeeds, Rekognition fails deep in the
    // pipeline, and the browser shows an unexplained FAIL minutes later.
    if (!res.ok) throw new Error(`Could not load ${path} (${res.status})`);
    return new File([await res.blob()], path.slice(1), {type: "image/png"});
  }

  // One click fills the whole form: eight fields plus both images. Any previous run is cleared
  // as well, so a stale verdict card can't sit next to freshly loaded data.
  async function loadScenario() {
    setLoadingCase(true);
    setError(null);
    try {
      const [licenseFile, selfieFile] = await Promise.all([
        fileFrom("/demo_license.png"),
        fileFrom(scenario.selfie),
      ]);
      setDetails(scenario.details);
      setLicense(licenseFile);
      setSelfie(selfieFile);
      setStatus(null);
      setUuid(null); // also stops the polling effect from the previous submission
      setCasesOpen(false);
    } catch (e) {
      setError(e instanceof Error ? e.message : String(e));
    } finally {
      setLoadingCase(false);
    }
  }

  async function copyField(field: string, value: string) {
    // await navigator.clipboard.writeText(value);
    // setCopiedField(field);
    // setTimeout(() => setCopiedField(null), 1200);

    //For S3, since endpoint is HTTP-only and navigator.clipboard does not exist
    // out of a secure context. execCommand is deprecated but its what works for this scenario
    // Is dropped once CloudFront puts the site on HTTPS
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
        // The attempts cap above is unreachable when fetchStatus throws, so without this a
        // failing endpoint polls every 3s forever. Keep retrying (a blip shouldn't end the
        // run) but honour the same ~2 min ceiling.
        if (attempts >= 40 && timer.current) clearInterval(timer.current);
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
    // Load-bearing now that the form starts empty: without it an untouched Submit uploads a
    // CSV of blank strings, burns a real pipeline run, and comes back FAIL looking like a
    // backend fault. Named fields rather than a generic "fill everything in" so the fix is
    // one glance - unless nothing is filled at all, where listing all eight is just noise.
    const missing = LICENSE_FIELDS.filter((f) => !details[f].trim());
    if (missing.length){
      setError(
        missing.length === LICENSE_FIELDS.length
          ? "Fill in the applicant details, or load a test case from the header."
          : `Missing: ${missing.map(pretty).join(", ")}.`
      );
      return;
    }
    if (!license || !selfie){
      setError("Pick both a license image and a selfie.");
      return;
    }
    setError(null);
    setBusy(true);
    setStatus(null);
    // Also clear the id, not just the flags: if this submit throws before setUuid(id) below,
    // the Result card is still keyed on the *previous* run and would show that run's verdict
    // sitting under this run's error message.
    setUuid(null);
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
          {/* The three real fixtures from TestZipUpload/, each one click away from being loaded
              into the form. Replaces the old single "Demo data" panel: that one only ever
              described the happy path, and the two failure modes are the interesting half of
              this pipeline. Rows still copy on click for anyone editing a value by hand. */}
          <Popover open={casesOpen} onOpenChange={setCasesOpen}>
            <PopoverTrigger className={headerButton}>Test cases</PopoverTrigger>
            <PopoverContent align={"end"} className={"w-[22rem] bg-surface text-ink ring-ink/10"}>
              <p className={"font-mono text-[10px] uppercase tracking-[0.2em] text-ink/65"}>
                Test cases (Copy paste + download/upload pictures manually, or auto load a case)
              </p>
              {/* aria-pressed carries the selection for screen readers; the visual cue is an
                  inverted fill (luminance, not hue) so it survives colour-blindness too. */}
              <div role={"group"} aria-label={"Test case"} className={"flex gap-1 rounded-md border border-line p-1"}>
                {SCENARIOS.map((s) => (
                  <button
                    key={s.id}
                    type={"button"}
                    onClick={() => setScenarioId(s.id)}
                    aria-pressed={s.id === scenarioId}
                    className={
                      "flex-1 cursor-pointer rounded px-2 py-2 font-mono text-[10px] uppercase " +
                      "tracking-[0.12em] transition-colors duration-200 " +
                      (s.id === scenarioId
                        ? "bg-ink text-paper"
                        : "text-ink/65 hover:bg-thread/[0.06] hover:text-ink")
                    }
                  >
                    {s.tab}
                  </button>
                ))}
              </div>
              <div>
                <p className={"font-mono text-[10px] uppercase tracking-[0.16em] text-ink"}>
                  {scenario.expect}
                </p>
                <p className={"mt-1 text-[13px] leading-5 text-ink/65"}>{scenario.blurb}</p>
              </div>
              <div className={"flex flex-col overflow-hidden rounded-md border border-line"}>
                {Object.entries(scenario.details).map(([field, value]) => {
                  const wrong = scenario.wrong.includes(field as LicenseField);
                  return (
                    <button
                      key={field}
                      type={"button"}
                      onClick={() => copyField(field, value)}
                      className={
                        "flex items-center justify-between gap-3 border-b border-line/70 px-2.5 py-1.5 " +
                        "text-left transition-colors duration-200 last:border-b-0 hover:bg-thread/[0.06] " +
                        (wrong ? "border-l-2 border-l-fail" : "")
                      }
                    >
                      <span className={"font-mono text-[10px] uppercase tracking-[0.12em] text-ink/65"}>
                        {pretty(field)}
                      </span>
                      <span className={"flex items-center gap-1.5"}>
                        {/* The left rule alone would be colour-only (WCAG 1.4.1), so the
                            mismatch says so in words as well. */}
                        {wrong && (
                          <span className={"font-mono text-[9px] uppercase tracking-[0.1em] text-fail"}>
                            ≠ licence
                          </span>
                        )}
                        {/* Swapping the value for "copied" keeps the confirmation off colour alone
                            (WCAG 1.4.1) - a tick-plus-green would carry the same meaning twice. */}
                        <span className={"font-mono text-[12px] text-ink"}>
                          {copiedField === field ? "copied" : value}
                        </span>
                      </span>
                    </button>
                  );
                })}
              </div>
              <button
                type={"button"}
                onClick={loadScenario}
                disabled={loadingCase}
                className={
                  "h-10 w-full cursor-pointer rounded-md bg-ink text-sm font-medium text-paper " +
                  "transition-colors duration-200 hover:bg-thread-strong " +
                  "disabled:cursor-not-allowed disabled:opacity-45"
                }
              >
                {loadingCase ? "Loading..." : "Load into form"}
              </button>
              {/* Kept for anyone testing the pickers by hand or uploading to S3 directly; the
                  download names match the pipeline's <uuid>_*.png convention. */}
              <div className={"flex gap-2"}>
                <a
                  href={"/demo_license.png"}
                  download={`${scenario.id}_license.png`}
                  className={downloadLink}
                >
                  Download Licence
                </a>
                <a
                  href={scenario.selfie}
                  download={`${scenario.id}_selfie.png`}
                  className={downloadLink}
                >
                  Download Selfie
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
              <span className={fieldLabel}>{pretty(field)}</span>
              {/* Controlled `value` + a STATIC placeholder, which is the whole trick: the hint
                  used to be `placeholder={details[field]}`, so the box was uncontrolled and
                  never re-rendered from state - loading a test case changed `details` (and the
                  CSV that gets submitted) while the field on screen sat there looking empty.
                  Now the grey text is only ever MOCK, and anything in ink is real state.
                  DobPicker below was already controlled, which is why the date was the one
                  field that appeared to move. */}
              <input
                value={details[field]}
                placeholder={MOCK[field]}
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
    // Thumbnail straight off the File via createObjectURL - no read, no base64, no upload:
    // the browser already has the bytes. Revoked on change/unmount or each new pick leaks
    // the previous blob for the life of the document.
    const preview = useMemo(() => (file ? URL.createObjectURL(file) : null), [file]);
    useEffect(() => () => {if (preview) URL.revokeObjectURL(preview);}, [preview]);

    // Native HTML5 drop. preventDefault on dragOver is what makes the label a drop target at
    // all; without it the browser navigates to the file instead. A drop bypasses the input's
    // accept="image/*", so the type check is here rather than left to the backend.
    const [over, setOver] = useState(false);

    // Empty and filled are visually distinct states: dashed + muted while waiting, solid with a
    // teal check once a file is attached. Colour alone never carries the meaning - the border
    // style and the tick both change (WCAG 1.4.1).
    return(
        <label
          onDragOver={(e) => {e.preventDefault(); setOver(true);}}
          // dragleave also fires when the cursor crosses onto a child (the thumbnail, the
          // labels), so an unconditional setOver(false) strobes the highlight. relatedTarget
          // is what's being entered - null when the drag leaves the window entirely.
          onDragLeave={(e) => {if (!e.currentTarget.contains(e.relatedTarget as Node | null)) setOver(false);}}
          onDrop={(e) => {
            e.preventDefault();
            setOver(false);
            const dropped = e.dataTransfer.files[0];
            if (dropped?.type.startsWith("image/")) onPick(dropped);
          }}
          className={
          "group flex min-h-[104px] cursor-pointer flex-col items-center justify-center gap-1 rounded-md border-2 p-4 text-center transition-colors duration-200 " +
          "focus-within:ring-2 focus-within:ring-thread/40 focus-within:ring-offset-2 focus-within:ring-offset-surface " +
          (over
            ? "border-solid border-thread bg-thread/10"
            : file
            ? "border-solid border-thread/40 bg-thread/[0.04]"
            : "border-dashed border-line hover:border-ink/30 hover:bg-ink/[0.02]")
        }>
          {/* alt="" on purpose: the img sits inside the <label>, so any alt text would be read
              out as part of the file input's accessible name, ahead of the label and filename
              that already say the same thing. max-w-full stops a wide image (a 6:1 crop at
              max-h-24 is ~576px) from pushing the tile past its grid column. */}
          {/* eslint-disable-next-line @next/next/no-img-element -- blob: URL, next/image can't optimize it */}
          {preview && <img src={preview} alt="" className={"mb-1 max-h-24 w-auto max-w-full rounded-sm border border-line object-contain"}/>}
          <span className={"flex items-center gap-1.5 text-sm font-medium text-ink/80"}>
            {file && (
              <svg aria-hidden viewBox="0 0 16 16" className="h-3.5 w-3.5 text-thread" fill="none" stroke="currentColor" strokeWidth="2.25" strokeLinecap="round" strokeLinejoin="round">
                <path d="M3 8.5 6.5 12 13 4.5" />
              </svg>
            )}
            {label}
          </span>
          <span className={"line-clamp-1 max-w-full break-all text-xs " + (file ? "text-ink/65" : "text-ink/65")}>
            {file ? file.name : `Click to choose or drop an image`}
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