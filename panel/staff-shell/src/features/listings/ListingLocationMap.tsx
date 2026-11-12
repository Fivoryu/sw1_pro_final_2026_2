import L from "leaflet";
import "leaflet/dist/leaflet.css";
import { useEffect, useRef, useState } from "react";

/** The tile server is configurable; the default is the public OpenStreetMap server. */
const TILE_URL =
  (import.meta.env.VITE_MAP_TILE_URL as string | undefined) ??
  "https://tile.openstreetmap.org/{z}/{x}/{y}.png";
const ATTRIBUTION =
  (import.meta.env.VITE_MAP_ATTRIBUTION as string | undefined) ??
  "© OpenStreetMap contributors";

const FALLBACK_CENTER: [number, number] = [-17.7833, -63.1821];
const FALLBACK_ZOOM = 12;
const POINT_ZOOM = 16;

interface ListingLocationMapProps {
  latitude: number | null;
  longitude: number | null;
  onChange: (latitude: number, longitude: number) => void;
}

// A CSS pin avoids Leaflet's default image icons, which Vite bundling cannot resolve.
const PIN_ICON = L.divIcon({ className: "location-pin", iconSize: [22, 22], iconAnchor: [11, 22] });

export function ListingLocationMap({ latitude, longitude, onChange }: ListingLocationMapProps) {
  const containerRef = useRef<HTMLDivElement>(null);
  const mapRef = useRef<L.Map | null>(null);
  const markerRef = useRef<L.Marker | null>(null);
  const onChangeRef = useRef(onChange);
  onChangeRef.current = onChange;
  const [tilesFailed, setTilesFailed] = useState(false);

  useEffect(() => {
    if (!containerRef.current) return;
    const map = L.map(containerRef.current, { attributionControl: false });
    map.setView(FALLBACK_CENTER, FALLBACK_ZOOM);
    L.tileLayer(TILE_URL, { maxZoom: 19 })
      .on("tileerror", () => setTilesFailed(true))
      .on("tileload", () => setTilesFailed(false))
      .addTo(map);
    map.on("click", (event: L.LeafletMouseEvent) =>
      onChangeRef.current(event.latlng.lat, event.latlng.lng),
    );
    mapRef.current = map;
    return () => {
      map.remove();
      mapRef.current = null;
      markerRef.current = null;
    };
  }, []);

  useEffect(() => {
    const map = mapRef.current;
    if (!map) return;
    if (latitude === null || longitude === null) {
      markerRef.current?.remove();
      markerRef.current = null;
      return;
    }
    if (markerRef.current) {
      markerRef.current.setLatLng([latitude, longitude]);
      return;
    }
    const marker = L.marker([latitude, longitude], { icon: PIN_ICON, draggable: true })
      .on("dragend", () => {
        const point = marker.getLatLng();
        onChangeRef.current(point.lat, point.lng);
      })
      .addTo(map);
    markerRef.current = marker;
    map.setView([latitude, longitude], POINT_ZOOM);
  }, [latitude, longitude]);

  return (
    <div className="location-map">
      <div
        aria-label="Mapa de ubicación del inmueble"
        className="location-map__canvas"
        ref={containerRef}
        role="application"
      />
      {tilesFailed ? (
        <p className="review-queue__message review-queue__message--error" role="alert">
          No se pudo cargar el mapa. Revisa tu conexión o inténtalo más tarde.
        </p>
      ) : null}
      <p className="location-map__attribution">{ATTRIBUTION}</p>
    </div>
  );
}
