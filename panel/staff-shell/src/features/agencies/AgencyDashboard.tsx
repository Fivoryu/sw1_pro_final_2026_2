// panel/staff-shell/src/features/agencies/AgencyDashboard.tsx

import React, { useEffect, useState } from "react"; // <-- Agregamos 'React' aquí
import { fetchAgencyMetrics, AgencyMetricsResponse } from "../../application/agencyMetricsApi";

interface AgencyDashboardProps {
  agencyId: string;
  accessToken: string; // <--- 1. EXIGIMOS EL TOKEN AQUÍ
}

export function AgencyDashboard({ agencyId, accessToken }: AgencyDashboardProps) { // <--- 2. LO RECIBIMOS AQUÍ
  const [metrics, setMetrics] = useState<AgencyMetricsResponse | null>(null);
  const [error, setError] = useState<string | null>(null);
  const [loading, setLoading] = useState<boolean>(true);

  useEffect(() => {
    setLoading(true);
    fetchAgencyMetrics(accessToken, agencyId) // <--- 3. SE LO PASAMOS A LA FUNCIÓN
      .then((data) => setMetrics(data))
      .catch((err: Error) => setError(err.message))
      .finally(() => setLoading(false));
  }, [agencyId, accessToken]); // <--- 4. LO AÑADIMOS A LAS DEPENDENCIAS

  if (loading) return <div style={{ padding: '20px' }}>Cargando métricas del panel...</div>;
  if (error) return <div style={{ padding: '20px', color: 'red' }}>Error: {error}</div>;
  if (!metrics) return null;

  return (
    <div style={{ padding: '32px 0', fontFamily: 'inherit' }}>
      <p style={{ fontSize: '0.75rem', fontWeight: 700, color: '#1b4b43', letterSpacing: '0.1em', textTransform: 'uppercase', marginBottom: '8px' }}>
        Resumen Estadístico
      </p>
      <h1 style={{ fontSize: '2.5rem', fontWeight: 400, color: '#111', margin: '0 0 32px 0', letterSpacing: '-0.02em' }}>
        Métricas de la Agencia
      </h1>
      
      <div style={{ display: 'grid', gridTemplateColumns: 'repeat(auto-fit, minmax(300px, 1fr))', gap: '24px' }}>
        
        {/* Tarjeta Inmuebles */}
        <div style={{ backgroundColor: '#ffffff', border: '1px solid #e5e7eb', borderRadius: '12px', padding: '24px', boxShadow: '0 4px 6px -1px rgba(0, 0, 0, 0.05)' }}>
          <h3 style={{ marginTop: 0, fontSize: '1.25rem', color: '#1b4b43', borderBottom: '2px solid #f3f4f6', paddingBottom: '16px', fontWeight: 600 }}>
            Publicaciones
          </h3>
          <div style={{ display: 'flex', flexDirection: 'column', gap: '16px', marginTop: '16px' }}>
            <div style={{ display: 'flex', justifyContent: 'space-between', alignItems: 'center' }}>
              <span style={{ color: '#4b5563', fontSize: '1rem' }}>Borradores</span>
              <span style={{ fontWeight: 600, fontSize: '1.2rem', color: '#111' }}>{metrics.listings.draft}</span>
            </div>
            <div style={{ display: 'flex', justifyContent: 'space-between', alignItems: 'center' }}>
              <span style={{ color: '#4b5563', fontSize: '1rem' }}>En revisión</span>
              <span style={{ fontWeight: 600, fontSize: '1.2rem', color: '#d97706' }}>{metrics.listings.in_review}</span>
            </div>
            <div style={{ display: 'flex', justifyContent: 'space-between', alignItems: 'center' }}>
              <span style={{ color: '#4b5563', fontSize: '1rem' }}>Publicados</span>
              <span style={{ fontWeight: 600, fontSize: '1.2rem', color: '#059669' }}>{metrics.listings.published}</span>
            </div>
          </div>
        </div>

        {/* Tarjeta Cotizaciones */}
        <div style={{ backgroundColor: '#ffffff', border: '1px solid #e5e7eb', borderRadius: '12px', padding: '24px', boxShadow: '0 4px 6px -1px rgba(0, 0, 0, 0.05)', display: 'flex', flexDirection: 'column' }}>
          <h3 style={{ marginTop: 0, fontSize: '1.25rem', color: '#1b4b43', borderBottom: '2px solid #f3f4f6', paddingBottom: '16px', fontWeight: 600 }}>
            Cotizaciones
          </h3>
          <div style={{ flex: 1, display: 'flex', flexDirection: 'column', justifyContent: 'center', alignItems: 'center', marginTop: '16px' }}>
             <span style={{ fontSize: '4rem', fontWeight: 300, color: '#111', lineHeight: '1' }}>
               {metrics.active_quotes}
             </span>
             <span style={{ color: '#6b7280', fontSize: '1rem', marginTop: '8px', textTransform: 'uppercase', letterSpacing: '0.05em' }}>
               Cotizaciones Vigentes
             </span>
          </div>
        </div>

        {/* Tarjeta Reservas */}
        <div style={{ backgroundColor: '#ffffff', border: '1px solid #e5e7eb', borderRadius: '12px', padding: '24px', boxShadow: '0 4px 6px -1px rgba(0, 0, 0, 0.05)' }}>
          <h3 style={{ marginTop: 0, fontSize: '1.25rem', color: '#1b4b43', borderBottom: '2px solid #f3f4f6', paddingBottom: '16px', fontWeight: 600 }}>
            Estado de Reservas
          </h3>
          <div style={{ display: 'flex', flexDirection: 'column', gap: '12px', marginTop: '16px' }}>
            <div style={{ display: 'flex', justifyContent: 'space-between', alignItems: 'center' }}>
              <span style={{ color: '#4b5563' }}>Pendientes</span>
              <span style={{ fontWeight: 600, color: '#111' }}>{metrics.reservations.pending}</span>
            </div>
            <div style={{ display: 'flex', justifyContent: 'space-between', alignItems: 'center' }}>
              <span style={{ color: '#4b5563' }}>Aceptadas</span>
              <span style={{ fontWeight: 600, color: '#059669' }}>{metrics.reservations.accepted}</span>
            </div>
            <div style={{ display: 'flex', justifyContent: 'space-between', alignItems: 'center' }}>
              <span style={{ color: '#4b5563' }}>Rechazadas</span>
              <span style={{ fontWeight: 600, color: '#dc2626' }}>{metrics.reservations.rejected}</span>
            </div>
            <div style={{ display: 'flex', justifyContent: 'space-between', alignItems: 'center' }}>
              <span style={{ color: '#4b5563' }}>Canceladas</span>
              <span style={{ fontWeight: 600, color: '#6b7280' }}>{metrics.reservations.cancelled}</span>
            </div>
            <div style={{ display: 'flex', justifyContent: 'space-between', alignItems: 'center' }}>
              <span style={{ color: '#4b5563' }}>Vencidas</span>
              <span style={{ fontWeight: 600, color: '#d97706' }}>{metrics.reservations.expired}</span>
            </div>
          </div>
        </div>

      </div>
    </div>
  );
}