import { useState } from "react";

const PANEL_PATH = "/panel";

const BILLING_DISCOUNT_LABEL = "15% de descuento";

const PLANS = [
  {
    name: "Básico",
    monthlyPrice: 29,
    annualPrice: 25,
    popular: false,
    features: [
      "Hasta 5 inmuebles publicados",
      "Hasta 2 agentes con app de captura",
      "Recorridos 3D incluidos",
      "Soporte por correo",
    ],
  },
  {
    name: "Profesional",
    monthlyPrice: 79,
    annualPrice: 67,
    popular: true,
    features: [
      "Hasta 25 inmuebles publicados",
      "Hasta 10 agentes con app de captura",
      "Reservas con escrow y multi-moneda",
      "Inventario asistido de mobiliario",
      "Soporte prioritario",
    ],
  },
  {
    name: "Corporativo",
    monthlyPrice: 199,
    annualPrice: 169,
    popular: false,
    features: [
      "Inmuebles y agentes ilimitados",
      "Escrow y multi-moneda",
      "Administración multi-agencia",
      "Integración y onboarding dedicados",
      "Soporte 24/7",
    ],
  },
];

const STEPS = [
  {
    title: "La agencia publica el inmueble",
    description:
      "El personal de la inmobiliaria carga el inmueble, su moneda y las fotos desde el panel de administración.",
  },
  {
    title: "El agente captura el espacio",
    description:
      "Con la app de captura, el agente registra videos y fotos del inmueble para la reconstrucción del recorrido 3D.",
  },
  {
    title: "El cliente recorre y reserva",
    description:
      "El cliente explora el inmueble en 3D desde su teléfono, consulta la cotización y reserva con pago garantizado.",
  },
];

const AUDIENCES = [
  {
    title: "Inmobiliarias",
    description:
      "Administrá agencias, publicaciones y tipos de cambio desde un panel de staff con verificación en dos pasos.",
  },
  {
    title: "Agentes",
    description:
      "Capturá los espacios de cada inmueble desde la app móvil y seguí el estado de sus borradores.",
  },
  {
    title: "Clientes",
    description:
      "Recorré los inmuebles en 3D, cotizá en tu moneda y reservá sin moverte de donde estás.",
  },
];

const FEATURES = [
  {
    title: "Recorridos 3D",
    description:
      "Cada inmueble se transforma en una escena 3D navegable a partir de la captura del agente.",
  },
  {
    title: "Reservas con escrow",
    description:
      "El pago de la reserva queda retenido en un escrow hasta que la operación se completa.",
  },
  {
    title: "Cotizaciones multi-moneda",
    description:
      "Precios en BOB, USD y USDT con tipos de cambio administrados por el personal.",
  },
  {
    title: "Inventario asistido",
    description:
      "La detección de mobiliario sugiere el inventario del inmueble y el personal lo revisa antes de publicarlo.",
  },
];

export function LandingPage() {
  const [billing, setBilling] = useState<"monthly" | "annual">("monthly");

  return (
    <div className="landing">
      <header className="landing-header">
        <span className="landing-brand">RoomForge</span>
        <nav className="landing-nav" aria-label="Secciones de la landing">
          <a href="#como-funciona">Cómo funciona</a>
          <a href="#para-quien">Para quién</a>
          <a href="#precios">Precios</a>
          <a href="#ventajas">Ventajas</a>
        </nav>
        <a className="landing-button" href={PANEL_PATH}>
          Entrar al panel
        </a>
      </header>

      <main>
        <section className="landing-hero">
          <h1>Publicá inmuebles con recorridos 3D</h1>
          <p>
            RoomForge convierte la captura de tu agente en un recorrido 3D para
            que tus clientes exploren cada inmueble, coticen y reserven en línea.
          </p>
          <div className="landing-hero-actions">
            <a className="landing-button" href={PANEL_PATH}>
              Entrar al panel
            </a>
            <a className="landing-secondary" href="#como-funciona">
              Ver cómo funciona
            </a>
          </div>
        </section>

        <section className="landing-section" id="como-funciona">
          <h2>Cómo funciona</h2>
          <ol className="landing-steps">
            {STEPS.map((step, index) => (
              <li key={step.title}>
                <span className="landing-step-number">{index + 1}</span>
                <h3>{step.title}</h3>
                <p>{step.description}</p>
              </li>
            ))}
          </ol>
        </section>

        <section className="landing-section" id="para-quien">
          <h2>Para quién es</h2>
          <div className="landing-cards">
            {AUDIENCES.map((audience) => (
              <article key={audience.title}>
                <h3>{audience.title}</h3>
                <p>{audience.description}</p>
              </article>
            ))}
          </div>
        </section>

        <section className="landing-section" id="ventajas">
          <h2>Ventajas</h2>
          <div className="landing-cards">
            {FEATURES.map((feature) => (
              <article key={feature.title}>
                <h3>{feature.title}</h3>
                <p>{feature.description}</p>
              </article>
            ))}
          </div>
        </section>

        <section className="landing-section" id="precios">
          <h2>Precios</h2>
          <p className="landing-pricing-note">
            Elegí el plan de tu inmobiliaria. Con el pago anual ahorrás un 15%:
            12 meses por el precio de 10.
          </p>
          <div
            className="landing-billing-toggle"
            role="group"
            aria-label="Período de facturación"
          >
            <button
              type="button"
              aria-pressed={billing === "monthly"}
              onClick={() => setBilling("monthly")}
            >
              Mensual
            </button>
            <button
              type="button"
              aria-pressed={billing === "annual"}
              onClick={() => setBilling("annual")}
            >
              Anual · {BILLING_DISCOUNT_LABEL}
            </button>
          </div>
          <div className="landing-plans">
            {PLANS.map((plan) => (
              <article
                key={plan.name}
                className={
                  plan.popular ? "landing-plan is-popular" : "landing-plan"
                }
              >
                {plan.popular ? (
                  <span className="landing-plan-badge">Más elegido</span>
                ) : null}
                <h3>{plan.name}</h3>
                <p className="landing-plan-price">
                  <span className="landing-plan-amount">
                    ${billing === "monthly" ? plan.monthlyPrice : plan.annualPrice}
                  </span>
                  <span className="landing-plan-period">/ mes</span>
                </p>
                <p className="landing-plan-billing">
                  {billing === "annual"
                    ? `Facturado anualmente · $${plan.annualPrice * 12} al año`
                    : "Facturación mensual"}
                </p>
                {billing === "annual" ? (
                  <p className="landing-plan-savings">
                    Ahorrás ${(plan.monthlyPrice - plan.annualPrice) * 12} al año
                  </p>
                ) : null}
                <ul>
                  {plan.features.map((feature) => (
                    <li key={feature}>{feature}</li>
                  ))}
                </ul>
                <a
                  className={plan.popular ? "landing-button" : "landing-secondary"}
                  href={PANEL_PATH}
                >
                  Empezar ahora
                </a>
              </article>
            ))}
          </div>
        </section>

        <section className="landing-cta">
          <h2>Llevá tus inmuebles al 3D</h2>
          <a className="landing-button" href={PANEL_PATH}>
            Entrar al panel
          </a>
        </section>
      </main>

      <footer className="landing-footer">
        <span>RoomForge</span>
        <span>Proyecto académico · Ingeniería de Software 1 · Grupo #12</span>
      </footer>
    </div>
  );
}
