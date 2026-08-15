import Guilloche from "@/components/Guilloche";
import {plexMono, plexSans} from "@/app/fonts";
import type { Metadata } from "next";
import "./globals.css";
import ConfigureAmplify from "@/app/ConfigureAmplify";


export const metadata: Metadata = {
  title: "License Verification",
  description: "ACI Capstone 1",
};

export default function RootLayout({
  children,
}: Readonly<{
  children: React.ReactNode;
}>) {
  return (
    <html lang="en" className={`${plexSans.variable} ${plexMono.variable}`}>
      <body className="min-h-screen bg-paper text-ink antialiased">
      <ConfigureAmplify/>
      <Guilloche />
      {children}
      </body>
    </html>
  );
}
