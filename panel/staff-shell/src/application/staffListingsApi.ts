export type ListingApprovalStatus = "draft" | "pending" | "approved" | "rejected";

export type ListingReviewAction = "approve" | "reject" | "publish" | "unpublish";

export interface StaffListing {
  listing_id: string;
  agency_id: string;
  operation: "sale" | "rent";
  /** Decimal amount as serialized by the server; never recomputed here. */
  base_price: string;
  currency: "BOB" | "USD" | "USDT";
  city: string;
  zone: string;
  bedrooms: number;
  bathrooms: number;
  description: string | null;
  exact_address: string | null;
  approval_status: ListingApprovalStatus;
  is_published: boolean;
  offer_version: number;
  created_at: string;
}

export interface StaffListingPage {
  listings: StaffListing[];
  pagination: { limit: number; offset: number; total: number };
}

export interface ListingTransition {
  id: string;
  agency_id: string;
  listing_id: string;
  action: "create" | "edit" | "submit" | ListingReviewAction;
  from_status: string | null;
  from_published: boolean | null;
  to_status: string;
  to_published: boolean;
  observation: string | null;
  actor_id: string;
  actor_role: string;
  created_at: string;
}

export interface ListingFilter {
  status: ListingApprovalStatus;
}

export class StaffListingsApiError extends Error {
  constructor(
    readonly status: number,
    message: string,
  ) {
    super(message);
    this.name = "StaffListingsApiError";
  }
}

const PAGE_LIMIT = 50;

function listingsPath(agencyId: string): string {
  return `/api/v1/staff/agencies/${encodeURIComponent(agencyId)}/listings`;
}

function listingPath(agencyId: string, listingId: string): string {
  return `${listingsPath(agencyId)}/${encodeURIComponent(listingId)}`;
}

async function requestJson<T>(url: string, init: RequestInit): Promise<T> {
  const response = await fetch(url, init);

  if (!response.ok) {
    let message = "Listing request failed.";

    try {
      const payload: unknown = await response.json();
      if (
        typeof payload === "object" &&
        payload !== null &&
        "detail" in payload &&
        typeof payload.detail === "string"
      ) {
        message = payload.detail;
      }
    } catch {
      // Retain the generic message when the server has no JSON error body.
    }

    throw new StaffListingsApiError(response.status, message);
  }

  return (await response.json()) as T;
}

function authorizedGet(accessToken: string): RequestInit {
  return { method: "GET", headers: { Authorization: `Bearer ${accessToken}` } };
}

export function listAgencyListings(
  accessToken: string,
  agencyId: string,
  filter: ListingFilter,
): Promise<StaffListingPage> {
  const query = new URLSearchParams({
    status: filter.status,
    limit: String(PAGE_LIMIT),
  });
  return requestJson<StaffListingPage>(
    `${listingsPath(agencyId)}?${query.toString()}`,
    authorizedGet(accessToken),
  );
}

export function getAgencyListing(
  accessToken: string,
  agencyId: string,
  listingId: string,
): Promise<StaffListing> {
  return requestJson<StaffListing>(
    listingPath(agencyId, listingId),
    authorizedGet(accessToken),
  );
}

export function listListingTransitions(
  accessToken: string,
  agencyId: string,
  listingId: string,
): Promise<ListingTransition[]> {
  return requestJson<ListingTransition[]>(
    `${listingPath(agencyId, listingId)}/transitions`,
    authorizedGet(accessToken),
  );
}

export function transitionListing(
  accessToken: string,
  agencyId: string,
  listingId: string,
  action: ListingReviewAction,
  observation?: string,
): Promise<StaffListing> {
  return requestJson<StaffListing>(`${listingPath(agencyId, listingId)}/${action}`, {
    method: "POST",
    headers: {
      Authorization: `Bearer ${accessToken}`,
      "Content-Type": "application/json",
    },
    body: JSON.stringify(observation === undefined ? {} : { observation }),
  });
}
