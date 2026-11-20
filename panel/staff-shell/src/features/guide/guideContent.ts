export interface GuideStep {
  title: string;
  detail: string;
}

export interface GuideTopic {
  heading: string;
  intro: string;
  steps: GuideStep[];
  tips: string[];
}

export type GuideScreenId = "listing-review-queue";

/** Deterministic, rule-based guide content keyed by screen. No external calls. */
export const GUIDE_TOPICS: Record<GuideScreenId, GuideTopic> = {
  "listing-review-queue": {
    heading: "Cómo revisar un inmueble",
    intro: "Esta guía solo te indica los pasos; no abre ni cambia ningún inmueble por ti.",
    steps: [
      {
        title: "Elige la pestaña de estado",
        detail: "Usa las pestañas de arriba para ver los inmuebles según su estado, por ejemplo En revisión.",
      },
      {
        title: "Abre un inmueble",
        detail: "Pulsa el botón Revisar de la fila del inmueble que quieras evaluar.",
      },
      {
        title: "Revisa los datos, las fotos y la escena",
        detail: "Comprueba el precio, la ubicación, las fotos y el recorrido 3D antes de decidir.",
      },
      {
        title: "Decide la acción",
        detail: "Usa Aprobar o Rechazar según corresponda; tu decisión queda en el historial.",
      },
    ],
    tips: ["Puedes volver a la lista sin decidir con el botón de regreso."],
  },
};
