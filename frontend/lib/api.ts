import {fetchAuthSession} from 'aws-amplify/auth';
import type {StatusResponse, UploadUrlResponse} from "@/lib/types";

// in prod => same origin "/api/..." a full URL in local dev
const API_BASE = process.env.NEXT_PUBLIC_API_BASE ?? "";

// Auth header from the current Cognito Session
async function authHeaders(): Promise<Record<string, string>> {
  const session = await fetchAuthSession(); //Ask amplify the current login session
  const token = session.tokens?.idToken?.toString(); // pull ID token out of it ('?.' means "if it exists, otherwise skip and undefined")
  return token ? { Authorization: `Bearer ${token}` } : {}; // if there is a token, return {Authorization: "Bearer <token>"} to attach to request, if not return {} (no header, req is unauthenticated)
}

// 1) Ask Backend for a one time presigned S3 PUT URL + app uuid to actually upload the zip
export async function requestUploadUrl(): Promise<UploadUrlResponse> {
    const res = await fetch(`${API_BASE}/api/upload-url`,
        {
         method: "POST",
         headers: await authHeaders(),
        }); //sends POST req to /api/upload-url with header attached

    //if header has error (like 404 or 500), throw error instead of keep going with bad data
    if (!res.ok) throw new Error(`upload-url failed: ${res.status}`);
    return (await res.json()) as UploadUrlResponse //says to trust that this matches UploadUrlResponse shape ({uuid, url, key}) from types.ts
}

// 2) Upload the zip into S3 with presigned URL (no auth header
//      because signature is the auth). Trigger for pipeline
export async function uploadZip(url:string, zip:Blob): Promise<void> { //<void> becuase it does not return any data, just succeeds or throws
    const res = await fetch(url, {method: "PUT", body:zip}); //sends Blob directly to presigned url you get from requestUploadUrl()
    if (!res.ok) throw new Error(`S3 upload failed: ${res.status}`);
}

// 3) Poll the pipeline's result flags by uuid
export async function fetchStatus(uuid:string): Promise<StatusResponse> {
    const res = await fetch(`${API_BASE}/api/status/${uuid}`, //sends GET (default) to backend's status endpoint, uuid added to it plus header
        {headers: await authHeaders(),});
    if (!res.ok) throw new Error(`status failed: ${res.status}`);
    return (await res.json()) as StatusResponse;
    // ^^^ tells TS to treat it as ({ status, LICENSE_SELFIE_MATCH?, LICENSE_DETAILS_MATCH?, LICENSE_VALIDATION? })
}
