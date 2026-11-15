import { act, render, screen } from "@testing-library/react";
import { beforeEach, describe, expect, it, vi } from "vitest";

type Handler = (event?: unknown) => void;
const state = vi.hoisted(() => ({
  mapHandlers: {} as Record<string, Handler>,
  tileHandlers: {} as Record<string, Handler>,
  tileUrl: "",
  marker: null as null | { latlng: [number, number]; handlers: Record<string, Handler> },
  removed: false,
  view: null as null | { center: [number, number]; zoom: number },
}));

vi.mock("leaflet", () => {
  const map = {
    setView(center: [number, number], zoom: number) {
      state.view = { center, zoom };
      return map;
    },
    on(name: string, handler: Handler) {
      state.mapHandlers[name] = handler;
      return map;
    },
    remove() {
      state.removed = true;
    },
  };
  const api = {
    map: () => map,
    tileLayer: (url: string) => {
      state.tileUrl = url;
      const layer = {
        addTo: () => layer,
        on(name: string, handler: Handler) {
          state.tileHandlers[name] = handler;
          return layer;
        },
      };
      return layer;
    },
    divIcon: (options: unknown) => options,
    marker: (latlng: [number, number]) => {
      const entry = { latlng, handlers: {} as Record<string, Handler> };
      state.marker = entry;
      const marker = {
        addTo: () => marker,
        on(name: string, handler: Handler) {
          entry.handlers[name] = handler;
          return marker;
        },
        setLatLng(next: [number, number]) {
          entry.latlng = next;
          return marker;
        },
        getLatLng: () => ({ lat: entry.latlng[0], lng: entry.latlng[1] }),
        remove() {
          state.marker = null;
        },
      };
      return marker;
    },
  };
  return { default: api, ...api };
});

import { ListingLocationMap } from "./ListingLocationMap";

beforeEach(() => {
  state.mapHandlers = {};
  state.tileHandlers = {};
  state.marker = null;
  state.removed = false;
  state.view = null;
});

describe("ListingLocationMap", () => {
  it("uses OpenStreetMap by default and shows its attribution", () => {
    render(<ListingLocationMap latitude={null} longitude={null} onChange={vi.fn()} />);

    expect(state.tileUrl).toBe("https://tile.openstreetmap.org/{z}/{x}/{y}.png");
    expect(screen.getByText(/© OpenStreetMap contributors/)).toBeInTheDocument();
    expect(state.marker).toBeNull();
  });

  it("places a marker at the stored point and centres on it", () => {
    render(<ListingLocationMap latitude={-16.5} longitude={-68.1} onChange={vi.fn()} />);

    expect(state.marker?.latlng).toEqual([-16.5, -68.1]);
    expect(state.view?.center).toEqual([-16.5, -68.1]);
  });

  it("reports clicks and marker drags as the new point", () => {
    const onChange = vi.fn();
    render(<ListingLocationMap latitude={-16.5} longitude={-68.1} onChange={onChange} />);

    act(() => state.mapHandlers.click({ latlng: { lat: 10, lng: 20 } }));
    expect(onChange).toHaveBeenLastCalledWith(10, 20);

    act(() => {
      state.marker!.latlng = [30, 40];
      state.marker!.handlers.dragend();
    });
    expect(onChange).toHaveBeenLastCalledWith(30, 40);
  });

  it("shows a visible error when tiles fail to load and clears it when one loads", () => {
    render(<ListingLocationMap latitude={null} longitude={null} onChange={vi.fn()} />);

    act(() => state.tileHandlers.tileerror());
    expect(screen.getByRole("alert")).toHaveTextContent("No se pudo cargar el mapa");

    act(() => state.tileHandlers.tileload());
    expect(screen.queryByRole("alert")).not.toBeInTheDocument();
  });

  it("releases the map on unmount", () => {
    const view = render(<ListingLocationMap latitude={null} longitude={null} onChange={vi.fn()} />);
    view.unmount();
    expect(state.removed).toBe(true);
  });
});
