import { afterEach, expect, it, vi } from "vitest";
import { acceptCapture, getCapture, listCaptures } from "./captureReviewApi";
import { StaffListingsApiError } from "./staffListingsApi";

const body = { captureId: "cap-1", status: "completed", sceneDraft: null, warnings: [], failureReason: null };

afterEach(() => vi.unstubAllGlobals());

it("gets a capture with the bearer token and an encoded path", async () => {
  const fetchMock = vi.fn().mockResolvedValue({ ok: true, json: async () => body });
  vi.stubGlobal("fetch", fetchMock);
  await expect(getCapture("tok", "ag/1", "li-1", "cap-1")).resolves.toEqual(body);
  expect(fetchMock).toHaveBeenCalledWith(
    "/api/v1/staff/agencies/ag%2F1/listings/li-1/captures/cap-1",
    { method: "GET", headers: { Authorization: "Bearer tok" } },
  );
});

it("lists the captures of a listing", async () => {
  const fetchMock = vi.fn().mockResolvedValue({ ok: true, json: async () => ({ captures: [body] }) });
  vi.stubGlobal("fetch", fetchMock);
  await expect(listCaptures("tok", "ag-1", "li/1")).resolves.toEqual([body]);
  expect(fetchMock).toHaveBeenCalledWith(
    "/api/v1/staff/agencies/ag-1/listings/li%2F1/captures",
    { method: "GET", headers: { Authorization: "Bearer tok" } },
  );
});

it("accepts a capture with POST", async () => {
  const fetchMock = vi.fn().mockResolvedValue({ ok: true, json: async () => ({ ...body, status: "accepted" }) });
  vi.stubGlobal("fetch", fetchMock);
  await expect(acceptCapture("tok", "ag-1", "li-1", "cap-1")).resolves.toMatchObject({ status: "accepted" });
  expect(fetchMock).toHaveBeenCalledWith(
    "/api/v1/staff/agencies/ag-1/listings/li-1/captures/cap-1/accept",
    { method: "POST", headers: { Authorization: "Bearer tok" } },
  );
});

it("raises StaffListingsApiError with the HTTP status on failure", async () => {
  vi.stubGlobal("fetch", vi.fn().mockResolvedValue({ ok: false, status: 409 }));
  await expect(acceptCapture("tok", "a", "l", "c")).rejects.toMatchObject({ status: 409 });
  vi.stubGlobal("fetch", vi.fn().mockResolvedValue({ ok: false, status: 404 }));
  await expect(getCapture("tok", "a", "l", "c")).rejects.toBeInstanceOf(StaffListingsApiError);
});
