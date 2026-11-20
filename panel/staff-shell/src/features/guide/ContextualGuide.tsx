import { useEffect, useId, useRef, useState, type KeyboardEvent } from "react";
import { answerQuestion, getGreeting, getInitialChips } from "./guideAssistant";
import { GLOSSARY, GUIDE_TOPICS, type GuideScreenId } from "./guideContent";

const SECTIONS = [
  { id: "purpose", label: "Para qué sirve" },
  { id: "steps", label: "Paso a paso" },
  { id: "mistakes", label: "Errores comunes" },
  { id: "glossary", label: "Glosario" },
] as const;

type SectionId = (typeof SECTIONS)[number]["id"];

interface ChatMessage {
  id: number;
  role: "assistant" | "user";
  text: string;
}

/**
 * Help button that opens a chat-style assistant for one screen: the person
 * writes a question or taps a suggestion and gets an answer built from the
 * guide content. The full structured guide (purpose, walkthroughs, mistakes,
 * glossary) stays one tap away. It only explains and never triggers any
 * action of the screen.
 */
export function ContextualGuide({ screenId }: { screenId: GuideScreenId }) {
  const [open, setOpen] = useState(false);
  const [section, setSection] = useState<SectionId>("purpose");
  const [showFull, setShowFull] = useState(false);
  const [messages, setMessages] = useState<ChatMessage[]>([]);
  const [chips, setChips] = useState<string[]>([]);
  const [draft, setDraft] = useState("");
  const nextId = useRef(1);
  const inputRef = useRef<HTMLInputElement>(null);
  const logRef = useRef<HTMLDivElement>(null);
  const headingId = useId();
  const describedById = useId();
  const headingRef = useRef<HTMLHeadingElement>(null);
  const toggleRef = useRef<HTMLButtonElement>(null);
  const wasOpen = useRef(false);
  const topic = GUIDE_TOPICS[screenId];

  useEffect(() => {
    if (open) {
      if (inputRef.current) inputRef.current.focus();
      else headingRef.current?.focus();
    } else if (wasOpen.current) {
      toggleRef.current?.focus();
    }
    wasOpen.current = open;
  }, [open]);

  useEffect(() => {
    if (logRef.current) logRef.current.scrollTop = logRef.current.scrollHeight;
  }, [messages]);

  function openGuide() {
    if (messages.length === 0) {
      setMessages([{ id: nextId.current++, role: "assistant", text: getGreeting(screenId) }]);
      setChips(getInitialChips(screenId));
    }
    setOpen(true);
  }

  function ask(question: string) {
    const trimmed = question.trim();
    if (trimmed.length === 0) return;
    const answer = answerQuestion(trimmed, screenId);
    setMessages((current) => [
      ...current,
      { id: nextId.current++, role: "user", text: trimmed },
      { id: nextId.current++, role: "assistant", text: answer.text },
    ]);
    setChips(answer.chips);
    setDraft("");
  }

  function close() {
    setOpen(false);
    setShowFull(false);
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
          {showFull ? null : (
            <>
              <div aria-live="polite" className="contextual-guide__log" ref={logRef} role="log">
                {messages.map((message) => (
                  <p
                    className={`contextual-guide__message contextual-guide__message--${message.role}`}
                    key={message.id}
                  >
                    {message.text}
                  </p>
                ))}
              </div>
              <div aria-label="Sugerencias" className="contextual-guide__chips" role="group">
                {chips.map((chip) => (
                  <button
                    className="contextual-guide__chip"
                    key={chip}
                    onClick={() => ask(chip)}
                    type="button"
                  >
                    {chip}
                  </button>
                ))}
              </div>
              <div className="contextual-guide__composer">
                <input
                  aria-label="Escribe tu pregunta"
                  className="contextual-guide__input"
                  maxLength={200}
                  onChange={(event) => setDraft(event.target.value)}
                  onKeyDown={(event) => {
                    if (event.key === "Enter" && !event.nativeEvent.isComposing) {
                      event.preventDefault();
                      event.stopPropagation();
                      ask(draft);
                    }
                  }}
                  placeholder="Escribe tu pregunta"
                  ref={inputRef}
                  type="text"
                  value={draft}
                />
                <button onClick={() => ask(draft)} type="button">
                  Enviar
                </button>
              </div>
            </>
          )}
          <button
            className="contextual-guide__link"
            onClick={() => setShowFull((current) => !current)}
            type="button"
          >
            {showFull ? "Volver al chat" : "Ver guía completa"}
          </button>
          {showFull ? (
            <>
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
            </>
          ) : null}
          <button onClick={close} type="button">
            Cerrar guía
          </button>
        </aside>
      ) : (
        <>
          <button
            aria-describedby={describedById}
            className="contextual-guide__toggle"
            onClick={openGuide}
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
