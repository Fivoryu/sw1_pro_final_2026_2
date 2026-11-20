import { useEffect, useId, useRef, useState, type KeyboardEvent } from "react";
import { GLOSSARY, GUIDE_TOPICS, type GuideScreenId } from "./guideContent";

const SECTIONS = [
  { id: "purpose", label: "Para qué sirve" },
  { id: "steps", label: "Paso a paso" },
  { id: "mistakes", label: "Errores comunes" },
  { id: "glossary", label: "Glosario" },
] as const;

type SectionId = (typeof SECTIONS)[number]["id"];

/**
 * Help button that opens a panel with the purpose, walkthroughs, common
 * mistakes and glossary of one screen. It only displays guidance and never
 * triggers any action of the screen.
 */
export function ContextualGuide({ screenId }: { screenId: GuideScreenId }) {
  const [open, setOpen] = useState(false);
  const [section, setSection] = useState<SectionId>("purpose");
  const headingId = useId();
  const describedById = useId();
  const headingRef = useRef<HTMLHeadingElement>(null);
  const toggleRef = useRef<HTMLButtonElement>(null);
  const wasOpen = useRef(false);
  const topic = GUIDE_TOPICS[screenId];

  useEffect(() => {
    if (open) {
      headingRef.current?.focus();
    } else if (wasOpen.current) {
      toggleRef.current?.focus();
    }
    wasOpen.current = open;
  }, [open]);

  function close() {
    setOpen(false);
    setSection("purpose");
  }

  function handleKeyDown(event: KeyboardEvent<HTMLElement>) {
    if (event.key === "Escape") {
      event.stopPropagation();
      close();
    }
  }

  return (
    <div className="contextual-guide">
      {open ? (
        <aside
          aria-label="Guía"
          className="contextual-guide__panel"
          onKeyDown={handleKeyDown}
        >
          <h3 id={headingId} ref={headingRef} tabIndex={-1}>
            {topic.heading}
          </h3>
          <p className="contextual-guide__note">
            Esta guía solo te indica qué hacer; no ejecuta ninguna acción por ti.
          </p>
          <div aria-label="Secciones de la guía" className="contextual-guide__tabs" role="tablist">
            {SECTIONS.map((candidate) => (
              <button
                aria-selected={candidate.id === section}
                className="contextual-guide__tab"
                key={candidate.id}
                onClick={() => setSection(candidate.id)}
                role="tab"
                type="button"
              >
                {candidate.label}
              </button>
            ))}
          </div>
          <div className="contextual-guide__body" role="tabpanel">
            {section === "purpose" ? (
              <>
                <p>{topic.purpose}</p>
                <p className="contextual-guide__tip">Quién ve esta pantalla: {topic.audience}</p>
                <h4>Qué puedes hacer aquí</h4>
                <ul>
                  {topic.canDo.map((item) => (
                    <li key={item}>{item}</li>
                  ))}
                </ul>
              </>
            ) : null}
            {section === "steps"
              ? topic.walkthroughs.map((walkthrough) => (
                  <div key={walkthrough.title}>
                    <h4>{walkthrough.title}</h4>
                    <ol>
                      {walkthrough.steps.map((step) => (
                        <li key={step.title}>
                          <strong>{step.title}</strong>
                          <span>{step.detail}</span>
                        </li>
                      ))}
                    </ol>
                  </div>
                ))
              : null}
            {section === "mistakes" ? (
              <ul>
                {topic.mistakes.map((mistake) => (
                  <li key={mistake.problem}>
                    <strong>{mistake.problem}</strong>
                    <span>
                      <b>Qué hacer:</b> {mistake.fix}
                    </span>
                  </li>
                ))}
              </ul>
            ) : null}
            {section === "glossary" ? (
              <dl>
                {topic.glossary.map((key) => (
                  <div key={key}>
                    <dt>{GLOSSARY[key].term}</dt>
                    <dd>{GLOSSARY[key].meaning}</dd>
                  </div>
                ))}
              </dl>
            ) : null}
          </div>
          <button onClick={close} type="button">
            Cerrar guía
          </button>
        </aside>
      ) : (
        <>
          <button
            aria-describedby={describedById}
            className="contextual-guide__toggle"
            onClick={() => setOpen(true)}
            ref={toggleRef}
            type="button"
          >
            Guía
          </button>
          <span className="contextual-guide__hint" id={describedById}>
            Ayuda paso a paso: {topic.heading}
          </span>
        </>
      )}
    </div>
  );
}
