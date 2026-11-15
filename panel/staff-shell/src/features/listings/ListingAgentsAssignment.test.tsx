import { render, screen } from "@testing-library/react";
import userEvent from "@testing-library/user-event";
import { beforeEach, describe, expect, it, vi } from "vitest";
import {
  getListingAgents,
  ListingAgentsApiError,
  listAgencyAgents,
  putListingAgents,
} from "../../application/listingAgentsApi";
import { ListingAgentsAssignment } from "./ListingAgentsAssignment";

vi.mock("../../application/listingAgentsApi", async (importOriginal) => {
  const actual = await importOriginal<typeof import("../../application/listingAgentsApi")>();
  return {
    ...actual,
    listAgencyAgents: vi.fn(),
    getListingAgents: vi.fn(),
    putListingAgents: vi.fn(),
  };
});

const one = { id: "a1", email: "uno@example.test", active: true };
const two = { id: "a2", email: "dos@example.test", active: true };
const inactive = { id: "a3", email: "tres@example.test", active: false };

beforeEach(() => {
  vi.mocked(listAgencyAgents).mockReset().mockResolvedValue([one, two, inactive]);
  vi.mocked(getListingAgents).mockReset().mockResolvedValue([one]);
  vi.mocked(putListingAgents).mockReset();
});

describe("ListingAgentsAssignment", () => {
  it("shows only active agents with the assigned ones checked", async () => {
    render(<ListingAgentsAssignment accessToken="staff-access" agencyId="agency-1" listingId="l1" />);

    expect(await screen.findByRole("checkbox", { name: "uno@example.test" })).toBeChecked();
    expect(screen.getByRole("checkbox", { name: "dos@example.test" })).not.toBeChecked();
    expect(screen.queryByRole("checkbox", { name: "tres@example.test" })).not.toBeInTheDocument();
    expect(getListingAgents).toHaveBeenCalledWith("staff-access", "agency-1", "l1");
  });

  it("saves the full replacement list", async () => {
    const user = userEvent.setup();
    vi.mocked(putListingAgents).mockResolvedValue([two]);
    render(<ListingAgentsAssignment accessToken="staff-access" agencyId="agency-1" listingId="l1" />);

    await user.click(await screen.findByRole("checkbox", { name: "dos@example.test" }));
    await user.click(screen.getByRole("checkbox", { name: "uno@example.test" }));
    await user.click(screen.getByRole("button", { name: "Guardar asignación" }));

    expect(putListingAgents).toHaveBeenCalledWith("staff-access", "agency-1", "l1", ["a2"]);
    expect(await screen.findByRole("status")).toHaveTextContent("Agentes asignados guardados.");
  });

  it("shows the server error when saving fails", async () => {
    const user = userEvent.setup();
    vi.mocked(putListingAgents).mockRejectedValue(
      new ListingAgentsApiError(422, "Agent is inactive", "validation_error"),
    );
    render(<ListingAgentsAssignment accessToken="staff-access" agencyId="agency-1" listingId="l1" />);

    await user.click(await screen.findByRole("button", { name: "Guardar asignación" }));

    expect(await screen.findByRole("alert")).toHaveTextContent("Agent is inactive");
  });

  it("shows a load error with retry", async () => {
    const user = userEvent.setup();
    vi.mocked(listAgencyAgents).mockRejectedValueOnce(new ListingAgentsApiError(403, "Forbidden"));
    render(<ListingAgentsAssignment accessToken="staff-access" agencyId="agency-1" listingId="l1" />);

    expect(await screen.findByRole("alert")).toHaveTextContent("Forbidden");
    await user.click(screen.getByRole("button", { name: "Reintentar" }));
    expect(await screen.findByRole("checkbox", { name: "uno@example.test" })).toBeVisible();
  });
});
