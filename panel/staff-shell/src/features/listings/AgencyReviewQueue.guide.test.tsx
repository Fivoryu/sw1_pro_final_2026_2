import { render, screen, within } from "@testing-library/react";
import userEvent from "@testing-library/user-event";
import { beforeEach, describe, expect, it, vi } from "vitest";
import {
  getAgencyListing,
  getListingScene,
  listAgencyListings,
  listListingPhotos,
  listListingTransitions,
  StaffListingsApiError,
  transitionListing,
  type StaffListing,
} from "../../application/staffListingsApi";
import { AgencyReviewQueue } from "./AgencyReviewQueue";

vi.mock("../editor3d/SceneViewer", () => ({ SceneViewer: () => <div /> }));
vi.mock("./ListingLocationMap", () => ({ ListingLocationMap: () => <div /> }));
vi.mock("./ListingAgentsAssignment", () => ({ ListingAgentsAssignment: () => <div /> }));

vi.mock("../../application/staffListingsApi", async (importOriginal) => {
  const actual =
    await importOriginal<typeof import("../../application/staffListingsApi")>();
  return {
    ...actual,
    getAgencyListing: vi.fn(),
    getListingScene: vi.fn(),
    listAgencyListings: vi.fn(),
    listListingPhotos: vi.fn(),
    listListingTransitions: vi.fn(),
    transitionListing: vi.fn(),
  };
});

const item: StaffListing = {
  listing_id: "listing-1",
  agency_id: "agency-1",
  operation: "sale",
  base_price: "350000000.00",
  city: "Medellín",
  zone: "El Poblado",
  bedrooms: 3,
  bathrooms: 2,
  description: "Casa luminosa",
  exact_address: "Calle privada 123",
  latitude: null,
  longitude: null,
  currency: "BOB",
  approval_status: "pending",
  is_published: false,
  offer_version: 1,
  created_at: "2026-10-01T12:00:00Z",
};

beforeEach(() => {
  vi.mocked(listAgencyListings).mockReset().mockResolvedValue({
    listings: [item],
    pagination: { limit: 50, offset: 0, total: 1 },
  });
  vi.mocked(getAgencyListing).mockReset().mockResolvedValue(item);
  vi.mocked(transitionListing).mockReset();
  vi.mocked(listListingTransitions).mockReset().mockResolvedValue([]);
  vi.mocked(listListingPhotos).mockReset().mockResolvedValue([]);
  vi.mocked(getListingScene)
    .mockReset()
    .mockRejectedValue(new StaffListingsApiError(404, "no scene", "scene_not_defined"));
});

describe("review queue contextual guide", () => {
  it("opens a step list for the review screen without running any action", async () => {
    const user = userEvent.setup();
    render(<AgencyReviewQueue accessToken="t" agencyId="agency-1" />);
    await screen.findByRole("button", { name: /Revisar .*Medellín/ });
    vi.mocked(getAgencyListing).mockClear();

    expect(screen.queryByRole("complementary", { name: "Guía" })).toBeNull();
    await user.click(screen.getByRole("button", { name: "Guía" }));

    const panel = screen.getByRole("complementary", { name: "Guía" });
    expect(within(panel).getAllByRole("listitem").length).toBeGreaterThanOrEqual(3);
    expect(panel).toHaveTextContent("Revisar");

    // The guide only indicates: nothing was opened, approved or rejected.
    expect(getAgencyListing).not.toHaveBeenCalled();
    expect(transitionListing).not.toHaveBeenCalled();
    expect(screen.queryByRole("heading", { level: 3, name: /Medellín/ })).toBeNull();

    await user.click(screen.getByRole("button", { name: "Cerrar guía" }));
    expect(screen.queryByRole("complementary", { name: "Guía" })).toBeNull();
  });

  it("still opens the listing detail from the queue", async () => {
    const user = userEvent.setup();
    render(<AgencyReviewQueue accessToken="t" agencyId="agency-1" />);
    await user.click(await screen.findByRole("button", { name: /Revisar .*Medellín/ }));
    expect(await screen.findByRole("heading", { level: 3, name: /Medellín/ })).toBeVisible();
  });
});
