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
        return <p className={"mt-20 text-center text-slate-400 text-5xl"}>Loading...</p>
    }else{
        return (
        <div className="flex flex-col flex-1 items-center justify-center bg-zinc-50 font-sans dark:bg-black">
            <nav>NAV</nav>
            <SubmitPanel/>
        </div>
  );
    }




}
