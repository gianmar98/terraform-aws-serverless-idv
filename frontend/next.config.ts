import type { NextConfig } from "next";

const nextConfig: NextConfig = {
  /* config options here */
    output: "export", //built to static HTML/JS in ./out
    images: {unoptimized: true}, //Next Image optimizer needs a server, we dont have one
    //S3 website hosting needs a directory by its index doc, so every route needs to
    // be a directory. Without this, export writes login.html and a refresh on /login gives a 404 err
    trailingSlash: true,
};

export default nextConfig;
