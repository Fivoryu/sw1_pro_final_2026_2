import { ContextualGuide } from "../guide/ContextualGuide";
// panel/staff-shell/src/features/agencies/AgencyDashboard.tsx

import { useEffect, useState } from "react";
import {
  AgencyMetricsError,
  fetchAgencyMetrics,
  type AgencyMetricsResponse,
} from "../../application/agencyMetricsApi";

interface AgencyDashboardProps {
  agencyId: string;
  accessToken: string;
}

const cardStyle = {
  backgroundColor: "#ffffff",
  border: "1px solid #e5e7eb",
  borderRadius: "12px",
  padding: "24px",
  boxShadow: "0 4px 6px -1px rgba(0, 0, 0, 0.05)",
};

const cardTitleStyle = {
  marginTop: 0,
  fontSize: "1.25rem",
  color: "#1b4b43",
  borderBottom: "2px solid #f3f4f6",
  paddingBottom: "16px",
  fontWeight: 600,
};

function MetricRow({ label, value, color = "#111" }: { label: string; value: number; color?: string }) {
  return (
    <div style={{ display: "flex", justifyContent: "space-between", alignItems: "center" }}>
      <span style={{ color: "#4b5563", fontSize: "1rem" }}>{label}</span>
      <span style={{ fontWeight: 600, fontSize: "1.2rem", color }}>{value}</span>
    </div>
  );
}

function errorMessage(error: unknown): string {
  if (error instanceof AgencyMetricsError && error.status === 403) {
    return "Solo el administrador de la agencia puede ver estas métricas.";
  }
  return "No se pudieron cargar las métricas. Intentá de nuevo.";
}

export function AgencyDashboard({ agencyId, accessToken }: AgencyDashboardProps) {
  const [metrics, setMetrics] = useState<AgencyMetricsResponse | null>(null);
  const [error, setError] = useState<unknown>(null);
  const [loading, setLoading] = useState<boolean>(true);
  const [reload, setReload] = useState(0);

  useEffect(() => {
    let isCurrent = true;
    setLoading(true);
    setError(null);
    fetchAgencyMetrics(accessToken, agencyId)
      .then((data) => {
        if (isCurrent) setMetrics(data);
      })
      .catch((err: unknown) => {
        if (isCurrent) setError(err);
      })
      .finally(() => {
        if (isCurrent) setLoading(false);
      });
    return () => {
      isCurrent = false;
    };
  }, [agencyId, accessToken, reload]);

  if (loading) return <div style={{ padding: "20px" }}>Cargando métricas del panel...</div>;
  if (error) {
    const forbidden = error instanceof AgencyMetricsError && error.status === 403;
    return (
      <div role="alert" style={{ padding: "20px", color: "#b91c1c" }}>
        <p>{errorMessage(error)}</p>
        {forbidden ? null : (
          <button type="button" onClick={() => setReload((value) => value + 1)}>
            Reintentar
          </button>
        )}
      </div>
    );
  }
  if (!metrics) return null;

  return (
    <div style={{ padding: "32px 0", fontFamily: "inherit" }}>
      <p
        style={{
          fontSize: "0.75rem",
          fontWeight: 700,
          color: "#1b4b43",
          letterSpacing: "0.1em",
          textTransform: "uppercase",
          marginBottom: "8px",
        }}
      >
        Resumen Estadístico
      </p>
      <h1 style={{ fontSize: "2.5rem", fontWeight: 400, color: "#111", margin: "0 0 32px 0", letterSpacing: "-0.02em" }}>
        Métricas de la Agencia
      </h1>
      <ContextualGuide screenId="agency-dashboard" />

      <div style={{ display: "grid", gridTemplateColumns: "repeat(auto-fit, minmax(300px, 1fr))", gap: "24px" }}>
        <section aria-label="Publicaciones" style={cardStyle}>
          <h3 style={cardTitleStyle}>Publicaciones</h3>
          <div style={{ display: "flex", flexDirection: "column", gap: "16px", marginTop: "16px" }}>
            <MetricRow label="Borradores" value={metrics.listings.draft} />
            <MetricRow label="En revisión" value={metrics.listings.in_review} color="#d97706" />
            <MetricRow label="Publicados" value={metrics.listings.published} color="#059669" />
            <MetricRow label="Aprobados sin publicar" value={metrics.listings.approved_unpublished} color="#2563eb" />
            <MetricRow label="Rechazados" value={metrics.listings.rejected} color="#dc2626" />
            <div style={{ borderTop: "2px solid #f3f4f6", paddingTop: "12px" }}>
              <MetricRow label="Total de inmuebles" value={metrics.listings.total} />
            </div>
          </div>
        </section>

        <section aria-label="Cotizaciones" style={{ ...cardStyle, display: "flex", flexDirection: "column" }}>
          <h3 style={cardTitleStyle}>Cotizaciones</h3>
          <div style={{ flex: 1, display: "flex", flexDirection: "column", justifyContent: "center", alignItems: "center", marginTop: "16px" }}>
            <span style={{ fontSize: "4rem", fontWeight: 300, color: "#111", lineHeight: "1" }}>
              {metrics.active_quotes}
            </span>
            <span style={{ color: "#6b7280", fontSize: "1rem", marginTop: "8px", textTransform: "uppercase", letterSpacing: "0.05em" }}>
              Cotizaciones Vigentes
            </span>
          </div>
        </section>

        <section aria-label="Estado de Reservas" style={cardStyle}>
          <h3 style={cardTitleStyle}>Estado de Reservas</h3>
          <div style={{ display: "flex", flexDirection: "column", gap: "12px", marginTop: "16px" }}>
            <MetricRow label="Pendientes" value={metrics.reservations.pending} />
            <MetricRow label="Aceptadas" value={metrics.reservations.accepted} color="#059669" />
            <MetricRow label="Rechazadas" value={metrics.reservations.rejected} color="#dc2626" />
            <MetricRow label="Canceladas" value={metrics.reservations.cancelled} color="#6b7280" />
            <MetricRow label="Vencidas" value={metrics.reservations.expired} color="#d97706" />
          </div>
        </section>
      </div>
    </div>
  );
}
