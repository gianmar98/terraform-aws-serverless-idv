// Renders a passport-style MRZ from the submission id + applicant name.
export default function MrzStrip({ id, name }: { id: string; name: string }) {
  const parts = name.trim().split(/\s+/); //trim() removes outer spaces; split(...) splits any run of whitespace -["Giancarlo","Martinez"]
  const surname = (parts.at(-1) ?? "APPLICANT").toUpperCase();// at -1 grabs last name. if missing use APPLICANT instead
  const given = (parts[0] ?? "").toUpperCase();//at [0] get the first name
  // 44 chars is the real ICAO TD3 line width (what a passport actually uses); 30 just looked
  // arbitrary. The content is still cosmetic - no check digits, no nationality or expiry.
  const pad = (s: string) => s.padEnd(44, "<").slice(0, 44);
  const line1 = pad(`V<USA${surname}<<${given}`); // V<USAMARTINEZ<<GIANCARLO<<<...
  const line2 = pad(`${id.toUpperCase()}<<<USA`); // 72D81442<<<USA<<<...
  return (
    <figure className="mt-4">
      <figcaption className="mb-1.5 font-mono text-[10px] uppercase tracking-[0.2em] text-ink/65">
        Submission record
      </figcaption>
      {/* Decorative: the id and name it encodes are both already on screen in plain text.
          aria-hidden so a screen reader doesn't read out the filler "<" one by one. */}
      <div
        aria-hidden
        className="overflow-x-auto rounded-md bg-ink px-3 py-2 font-mono text-[11px] leading-5 tracking-[0.15em] text-paper"
      >
        <div>{line1}</div>
        <div>{line2}</div>
      </div>
    </figure>
  );
}
