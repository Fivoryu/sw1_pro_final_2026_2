import { StaffListingsApiError } from "./staffListingsApi";
import type { SceneDocument } from "./sceneContract";

export type CaptureStatus = "awaiting_upload" | "queued" | "processing" | "completed" | "failed" | "accepted";

export interface CaptureReview {
  captureId: string;
  status: CaptureStatus;
  sceneDraft: SceneDocument | null;
  warnings: string[];
  failureReason: string | null;
}

function capturesPath(agencyId: string, listingId: string) {
  return `/api/v1/staff/agencies/${encodeURIComponent(agencyId)}/listings/${encodeURIComponent(listingId)}/captures`;
}

function capturePath(agencyId: string, listingId: string, captureId: string) {
  return `${capturesPath(agencyId, listingId)}/${encodeURIComponent(captureId)}`;
}

async function request<T = CaptureReview>(
  token: string, url: string, method: "GET" | "POST", failure: string,
): Promise<T> {
  const response = await fetch(url, { method, headers: { Authorization: `Bearer ${token}` } });
  if (!response.ok) throw new StaffListingsApiError(response.status, failure);
  return await response.json() as T;
}

/** The listing's captures, newest first. */
export async function listCaptures(token: string, agencyId: string, listingId: string) {
  const body = await request<{ captures: CaptureReview[] }>(
    token, capturesPath(agencyId, listingId), "GET", "No se pudieron consultar las capturas.");
  return body.captures;
}

export function getCapture(token: string, agencyId: string, listingId: string, captureId: string) {
  return request(token, capturePath(agencyId, listingId, captureId), "GET", "No se pudo consultar la captura.");
}

export function acceptCapture(token: string, agencyId: string, listingId: string, captureId: string) {
  return request(token, capturePath(agencyId, listingId, captureId) + "/accept", "POST", "No se pudo aceptar la captura.");
}
