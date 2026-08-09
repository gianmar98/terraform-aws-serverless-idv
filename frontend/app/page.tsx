"use client"


import SubmitPanel from "@/components/SubmitPanel";
import {useRouter} from "next/navigation";
import {getCurrentUser} from "aws-amplify/auth" //<<-- COGNITO AUTH
import {useEffect, useState} from "react";

export default function Home() {
    const router = useRouter();

    // null = still checking; true = known signed in
    const [signedIn, setSignedIn] = useState<boolean|null>(null);

    useEffect(() => {
        getCurrentUser() //->"is anyone logged in right now?"
          .then(() => setSignedIn(true)) //-> if someone "is" signed in (can show submit pannel with signedIn = true)
          .catch(() => router.push("/login"));//-> if "no one" is logged in (throw error, and redirect to login)

    }, [router]); //"only re run this effect if router changes between renders"

    if (signedIn ===null) {
        return (
            <div className="flex min-h-svh items-center justify-center" role="status" aria-live="polite">
                <p className="font-mono text-xs uppercase tracking-[0.2em] text-ink/40 motion-safe:animate-pulse">
                    Verifying session
                </p>
            </div>
        )
    }else{
        return (
        <div className="flex min-h-svh flex-col">
            {/* Wordmark per the 6.2 brief: Plex Sans 700, uppercase, wide tracking - an official
                document title rather than a logo. The hairline rule reads as a form's header rule. */}
            <header className="border-b border-line/70">
                <div className="mx-auto flex h-14 w-full max-w-2xl items-center gap-2.5 px-4">
                    <span aria-hidden className="h-4 w-1 rounded-full bg-thread" />
                    <span className="text-[13px] font-bold uppercase tracking-[0.22em] text-ink">
                        Identity Verification
                    </span>
                </div>
            </header>
            <main className="flex-1">
                <SubmitPanel/>
            </main>
        </div>
  );
    }



}
