import { StaffListingsApiError, type StaffListing } from "./staffListingsApi";
import type { ScenePoint3D } from "./sceneContract";

export interface FurnitureExtra {
  extra_id: string;
  name: string;
  price: string;
  quantity: number;
  width_cm: number | null;
  height_cm: number | null;
  depth_cm: number | null;
  origin: string | null;
  category: string | null;
  room: string | null;
  visual_reference: string | null;
}

export interface FurnitureSuggestion {
  job_id: string;
  detection_index: number;
  photo_id: string;
  model_id: string;
  label: string;
  score: number;
  box: number[];
  status: "pending" | "confirmed" | "rejected" | "expired";
  extra_id: string | null;
}

export interface VolumeSuggestion {
  capture_id: string;
  object_id: string;
  model_id: string;
  label: string;
  score: number;
  // Null once the capture draft no longer holds the object (expired or decided entries).
  position: ScenePoint3D | null;
  dimensions: { width: number; height: number; depth: number } | null;
  status: "pending" | "confirmed" | "rejected" | "expired";
  extra_id: string | null;
}

export interface FurnitureReviewView {
  listing: StaffListing & { extras: FurnitureExtra[] };
  suggestions: FurnitureSuggestion[];
  /** Absent on servers that predate volume suggestions; treat as empty. */
  volume_suggestions?: VolumeSuggestion[];
  history: {
    request_id: string;
    job_id: string | null;
    detection_index: number | null;
    action: "manual" | "confirmed" | "rejected";
    extra_id: string | null;
    actor_id: string;
    created_at: string;
    snapshot: Record<string, unknown>;
  }[];
}

export interface FurnitureCommand {
  request_id: string;
  expected_offer_version: number;
  action: "manual" | "confirmed" | "rejected";
  job_id?: string;
  detection_index?: number;
  capture_id?: string;
  object_id?: string;
  existing_extra_id?: string;
  item?: {
    name: string; price: string; width_cm: number; height_cm: number; depth_cm: number;
    position: ScenePoint3D; quantity: number; category?: string; room?: string;
  };
}

export interface DetectionJobStatus {
  job_id: string;
  photo_id: string;
  status: string;
  failure_reason: string | null;
}

function path(agencyId: string, listingId: string) {
  return `/api/v1/staff/agencies/${encodeURIComponent(agencyId)}/listings/${encodeURIComponent(listingId)}`;
}

async function request<T>(token: string, url: string, body?: FurnitureCommand): Promise<T> {
  const response = await fetch(url, {
    method: body ? "POST" : "GET",
    headers: { Authorization: `Bearer ${token}`, ...(body ? { "Content-Type": "application/json" } : {}) },
    ...(body ? { body: JSON.stringify(body) } : {}),
  });
  if (!response.ok) throw new StaffListingsApiError(response.status, "No se pudo completar la revisión.");
  return await response.json() as T;
}

export function getFurnitureReview(token: string, agencyId: string, listingId: string) {
  return request<FurnitureReviewView>(token, path(agencyId, listingId) + "/furniture-review");
}

export function reviewFurniture(token: string, agencyId: string, listingId: string, body: FurnitureCommand) {
  return request<FurnitureReviewView>(token, path(agencyId, listingId) + "/furniture-review", body);
}

export async function listDetectionJobs(token: string, agencyId: string, listingId: string) {
  return (await request<{ jobs: DetectionJobStatus[] }>(token, path(agencyId, listingId) + "/detections")).jobs;
}

export async function requestPhotoDetection(token: string, agencyId: string, listingId: string, photoId: string): Promise<DetectionJobStatus> {
  const response = await fetch(path(agencyId, listingId) + `/photos/${encodeURIComponent(photoId)}/detections`, {
    method: "POST", headers: { Authorization: `Bearer ${token}` },
  });
  if (!response.ok) throw new StaffListingsApiError(response.status, "No se pudo solicitar la detección.");
  return await response.json() as DetectionJobStatus;
}
