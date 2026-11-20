import { useId, useState } from "react";
import { GUIDE_TOPICS, type GuideScreenId } from "./guideContent";

/**
 * Floating help button that opens a step-by-step panel for one screen.
 * It only displays guidance and never triggers any action of the screen.
 */
export function ContextualGuide({ screenId }: { screenId: GuideScreenId }) {
  const [open, setOpen] = useState(false);
  const headingId = useId();
  const topic = GUIDE_TOPICS[screenId];

  return (
    <div className="contextual-guide">
      {open ? (
        <aside aria-label="Guía" className="contextual-guide__panel">
          <h3 id={headingId}>{topic.heading}</h3>
          <p>{topic.intro}</p>
          <ol>
            {topic.steps.map((step) => (
              <li key={step.title}>
                <strong>{step.title}</strong>
                <span>{step.detail}</span>
              </li>
            ))}
          </ol>
          {topic.tips.map((tip) => (
            <p className="contextual-guide__tip" key={tip}>
              {tip}
            </p>
          ))}
          <button onClick={() => setOpen(false)} type="button">
            Cerrar guía
          </button>
        </aside>
      ) : null}
      {!open ? (
        <button
          className="contextual-guide__toggle"
          onClick={() => setOpen(true)}
          type="button"
        >
          Guía
        </button>
      ) : null}
    </div>
  );
}
