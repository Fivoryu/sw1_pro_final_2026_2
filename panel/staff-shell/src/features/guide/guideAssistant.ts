import { GLOSSARY, GUIDE_SCREEN_IDS, GUIDE_TOPICS, type GuideScreenId } from "./guideContent";

/**
 * Deterministic, offline answer engine for the guide chat. It only reads the
 * guide content: no network, no model, and it never triggers screen actions.
 */

export interface AssistantAnswer {
  text: string;
  chips: string[];
}

const PURPOSE_CHIP = "¿Para qué sirve esta pantalla?";
const ERRORS_CHIP = "¿Qué errores son comunes?";
const MORE_CHIP = "¿Qué más puedo hacer en el sistema?";

const STOPWORDS = new Set(
  (
    "a al algo ante como con cual cuales cuando de del el ella ellos en entre es esa ese eso esta este esto " +
    "la las le les lo los me mi mis mas muy no o para pero por porque que se si sin sobre su sus te ti tu tus " +
    "un una uno unos unas y ya yo hay son ser soy estoy puedo puede quiero quisiera necesito hacer hago donde " +
    "significa significan quiere decir tengo debo pantalla sale salen salio aparece pasa sucede"
  ).split(" "),
);

/** Groups of words that mean the same thing for the person asking. */
const SYNONYMS: string[][] = [
  ["entrar", "entro", "entra", "ingresar", "ingreso", "acceder", "acceso", "login", "loguear", "loguearme", "logueo", "logeo", "iniciar", "conectar"],
  ["cerrar", "cierro", "cierra", "salir", "salgo", "desconectar", "logout"],
  ["clave", "contrasena", "contrasenas", "contrasenia", "password", "pass"],
  ["crear", "agregar", "anadir", "nuevo", "nueva"],
  ["publicar", "publico", "subir", "subo", "subirlo", "poner", "ponerlo", "linea"],
  ["borrar", "borro", "eliminar", "elimino", "quitar", "quito", "suprimir", "remover"],
  ["ver", "mostrar", "muestra", "muestran", "visualizar", "mirar", "consultar"],
  ["activar", "actibo", "activo", "habilitar"],
  ["error", "fallo", "falla", "problema"],
  ["precio", "costo", "valor"],
  ["pagar", "pago", "pagos", "cobrar", "cobro", "abonar"],
];

/** Domain words so common that matching only them must not count as understanding. */
const GENERIC = new Set(["inmueble", "inmuebles", "cliente", "clientes", "sistema", "panel", "ver", "error", "fallo", "falla", "problema"].map((w) => w.slice(0, 5)));

/** Words that only carry an intent (greeting, thanks, lost, purpose, errors, more). */
const GREETING_WORDS = new Set(["hola", "buenas", "buenos", "dias", "tardes", "noches", "hey", "saludos"]);
const THANKS_WORDS = new Set(["gracias", "genial", "perfecto", "muchas", "mil", "excelente"]);
const LOST_WORDS = new Set(["perdi", "perdido", "perdida", "ayuda", "ayudame", "auxilio", "entiendo", "nada", "favor", "porfa"]);
const PURPOSE_WORDS = new Set(["sirve", "pagina", "aqui", "vista", "ventana", "estoy"]);
const MISTAKE_WORDS = new Set(["errores", "problemas", "comunes", "frecuentes"]);
const MORE_WORDS = new Set(["otras", "cosas", "pantallas", "sistema", "aplicacion", "app", "panel"]);

function editDistanceAtMostOne(a: string, b: string): boolean {
  if (a === b) return true;
  if (Math.abs(a.length - b.length) > 1) return false;
  let i = 0;
  while (i < a.length && i < b.length && a[i] === b[i]) i += 1;
  if (a.length === b.length) return a.slice(i + 1) === b.slice(i + 1);
  const [longer, shorter] = a.length > b.length ? [a, b] : [b, a];
  return longer.slice(i + 1) === shorter.slice(i);
}

/** Fuzzy only between 5-letter stems, so it never applies to words shorter than 5 letters. */
function fuzzyStemMatch(query: string, candidate: string): boolean {
  return query.length === 5 && candidate.length === 5 && editDistanceAtMostOne(query, candidate);
}

function plainText(text: string): string {
  return text
    .toLowerCase()
    .normalize("NFD")
    .replace(/[̀-ͯ]/g, "")
    .replace(/[^a-z0-9\s]/g, " ")
    .replace(/\s+/g, " ")
    .trim();
}

export function normalizeText(text: string): string[] {
  return plainText(text)
    .split(" ")
    .filter((token) => token.length > 0 && !STOPWORDS.has(token));
}

/** Words whose 5-letter prefix would collide with an unrelated verb ("borrador" vs "borrar"). */
const STEM_OVERRIDES: Record<string, string> = { borrador: "borrad", borradores: "borrad" };

function stem(token: string): string {
  if (STEM_OVERRIDES[token]) return STEM_OVERRIDES[token];
  return token.length > 5 ? token.slice(0, 5) : token;
}

function expand(token: string): string[] {
  const group = SYNONYMS.find((words) => words.includes(token));
  return (group ?? [token]).map(stem);
}

type EntryKind = "purpose" | "walkthrough" | "mistake" | "glossary";

interface Field {
  stems: Set<string>;
  weight: number;
}

interface Entry {
  kind: EntryKind;
  /** Screen the entry belongs to; null for glossary terms shared by screens. */
  screen: GuideScreenId | null;
  fields: Field[];
  /** Normalized title, for exact label matches. */
  label: string;
  text: string;
  followUps: string[];
}

function field(text: string, weight: number): Field {
  return { stems: new Set(normalizeText(text).map(stem)), weight };
}

function bullets(items: string[]): string {
  return items.map((item) => `- ${item}`).join("\n");
}

function numbered(steps: { title: string; detail: string }[]): string {
  return steps.map((step, index) => `${index + 1}. ${step.title}: ${step.detail}`).join("\n");
}

function buildKnowledgeBase(): Entry[] {
  const entries: Entry[] = [];
  for (const id of GUIDE_SCREEN_IDS) {
    const topic = GUIDE_TOPICS[id];
    entries.push({
      kind: "purpose",
      screen: id,
      fields: [field(topic.heading, 3), field(`${topic.purpose} ${topic.canDo.join(" ")}`, 1)],
      label: normalizeText(topic.heading).join(" "),
      text: `${topic.purpose}\n\nAquí puedes:\n${bullets(topic.canDo)}`,
      followUps: [],
    });
    for (const walkthrough of topic.walkthroughs) {
      entries.push({
        kind: "walkthrough",
        screen: id,
        fields: [
          field(walkthrough.title, 3),
          field(walkthrough.steps.map((s) => `${s.title} ${s.detail}`).join(" "), 1),
        ],
        label: normalizeText(walkthrough.title).join(" "),
        text: `Así se hace «${walkthrough.title}»:\n${numbered(walkthrough.steps)}`,
        followUps: topic.walkthroughs.filter((w) => w !== walkthrough).map((w) => w.title),
      });
    }
    for (const mistake of topic.mistakes) {
      entries.push({
        kind: "mistake",
        screen: id,
        fields: [field(mistake.problem, 3), field(mistake.fix, 1)],
        label: normalizeText(mistake.problem).join(" "),
        text: `Problema: ${mistake.problem}\nQué hacer: ${mistake.fix}`,
        followUps: [],
      });
    }
  }
  for (const key of Object.keys(GLOSSARY) as (keyof typeof GLOSSARY)[]) {
    const item = GLOSSARY[key];
    entries.push({
      kind: "glossary",
      screen: null,
      fields: [field(item.term, 4), field(item.meaning, 1)],
      label: normalizeText(item.term).join(" "),
      text: `${item.term}: ${item.meaning}`,
      followUps: [],
    });
  }
  return entries;
}

let knowledgeBase: Entry[] | null = null;
function getKnowledgeBase(): Entry[] {
  knowledgeBase ??= buildKnowledgeBase();
  return knowledgeBase;
}

function glossaryChip(key: keyof typeof GLOSSARY): string {
  return `¿Qué significa ${GLOSSARY[key].term}?`;
}

export function getInitialChips(screenId: GuideScreenId): string[] {
  const topic = GUIDE_TOPICS[screenId];
  return [
    PURPOSE_CHIP,
    ...topic.walkthroughs.slice(0, 4).map((w) => w.title),
    ERRORS_CHIP,
    ...topic.glossary.slice(0, 2).map(glossaryChip),
    MORE_CHIP,
  ];
}

export function getGreeting(screenId: GuideScreenId): string {
  const topic = GUIDE_TOPICS[screenId];
  return (
    `¡Hola! Soy la guía de RoomForge. Estás en: ${topic.heading}.\n` +
    `Aquí puedes:\n${bullets(topic.canDo.slice(0, 3))}\n` +
    "Escribe tu pregunta o toca una sugerencia y te explico qué hacer; yo solo explico, no hago nada por ti."
  );
}

function pickChips(candidates: string[], asked: string): string[] {
  const seen = new Set<string>([asked]);
  const result: string[] = [];
  for (const chip of candidates) {
    if (!seen.has(chip)) {
      seen.add(chip);
      result.push(chip);
    }
    if (result.length === 4) break;
  }
  return result;
}

function fallback(screenId: GuideScreenId, asked: string): AssistantAnswer {
  const topic = GUIDE_TOPICS[screenId];
  return {
    text:
      "No estoy seguro de haber entendido tu pregunta, y prefiero no inventar. " +
      `En esta pantalla (${topic.heading}) puedo explicarte:\n${bullets(topic.walkthroughs.map((w) => w.title))}\n` +
      "También puedo decirte para qué sirve la pantalla o qué errores son comunes. Prueba con una sugerencia.",
    chips: pickChips(getInitialChips(screenId), asked),
  };
}

function otherScreens(screenId: GuideScreenId): AssistantAnswer {
  const list = GUIDE_SCREEN_IDS.filter((id) => id !== screenId).map((id) => GUIDE_TOPICS[id].heading);
  return {
    text:
      "Además de esta pantalla, la guía explica estos temas del sistema:\n" +
      `${bullets(list)}\nEscribe el tema que te interese y te digo en qué pantalla está.`,
    chips: pickChips(getInitialChips(screenId), MORE_CHIP),
  };
}

function answerWithEntry(entry: Entry, screenId: GuideScreenId, asked: string): AssistantAnswer {
  let text = entry.text;
  const chips: string[] = [...entry.followUps];
  const sharedAcrossScreens =
    entry.screen !== null &&
    getKnowledgeBase().some((other) => other !== entry && other.kind === entry.kind && other.text === entry.text);
  if (entry.screen && entry.screen !== screenId && !sharedAcrossScreens) {
    const target = GUIDE_TOPICS[entry.screen];
    text =
      `Eso se hace en otra pantalla: «${target.heading}». ` +
      "Para llegar, búscala en la navegación del panel y, cuando estés ahí, abre la Guía de esa pantalla.\n\n" +
      text;
  } else if (entry.kind === "glossary") {
    const users = GUIDE_SCREEN_IDS.filter((id) =>
      GUIDE_TOPICS[id].glossary.some((key) => normalizeText(GLOSSARY[key].term).join(" ") === entry.label),
    );
    if (users.length > 0 && !users.includes(screenId)) {
      text += `\nSe usa en las pantallas: ${users.slice(0, 3).map((id) => `«${GUIDE_TOPICS[id].heading}»`).join(", ")}.`;
    }
  }
  chips.push(ERRORS_CHIP, MORE_CHIP, ...getInitialChips(screenId));
  return { text, chips: pickChips(chips, asked) };
}

interface QueryGroup {
  stems: string[];
  /** The asked word is so common in the domain that matching only it proves little. */
  generic: boolean;
}

function toGroup(token: string): QueryGroup {
  return { stems: expand(token), generic: GENERIC.has(stem(token)) };
}

function scoreEntry(
  entry: Entry,
  groups: QueryGroup[],
  normalized: string,
  glossaryBoost: boolean,
): { score: number; coverage: number; missedStrict: number } {
  if (groups.length === 0) return { score: 0, coverage: 0, missedStrict: 0 };
  let missedStrict = 0;
  let score = 0;
  let matched = 0;
  let coveredWeight = 0;
  for (const group of groups) {
    let best = 0;
    for (const item of entry.fields) {
      if (group.stems.some((s) => item.stems.has(s))) {
        best = Math.max(best, item.weight);
      } else if (group.stems.some((s) => [...item.stems].some((c) => fuzzyStemMatch(s, c)))) {
        best = Math.max(best, item.weight * 0.9);
      }
    }
    if (best > 0) {
      matched += 1;
      coveredWeight += group.generic ? 0.5 : 1;
    } else if (!group.generic) {
      missedStrict += 1;
    }
    score += best;
  }
  score *= 0.5 + 0.5 * (matched / groups.length);
  if (entry.label === normalized) score += 10;
  if (entry.kind === "glossary") score *= glossaryBoost ? 2 : 0.5;
  if (entry.kind === "purpose") score *= 0.6;
  return { score, coverage: coveredWeight / groups.length, missedStrict };
}

const MIN_SCORE = 2;
/** With two or more meaningful words, the answer must cover at least this share of them. */
const MIN_COVERAGE = 0.5;

/** True when every meaningful word of the question belongs to the intent. */
function only(tokens: string[], intentWords: Set<string>): boolean {
  return tokens.every((token) => intentWords.has(token));
}

export function answerQuestion(question: string, screenId: GuideScreenId): AssistantAnswer {
  const topic = GUIDE_TOPICS[screenId];
  const raw = plainText(question).replace(/\binici\w* (la |mi )?sesion\b/g, "entrar");
  const tokens = normalizeText(raw);
  const here = pickChips(getInitialChips(screenId), "");

  // Words that belong to an intent which fired but left a real question behind are
  // dropped; the rest of the question is then answered normally.
  const intentWords = new Set<string>();

  if (/^(hola|buenas|buenos dias|buenas tardes|buenas noches|hey|saludos)\b/.test(raw)) {
    if (only(tokens, GREETING_WORDS)) return { text: getGreeting(screenId), chips: here };
    GREETING_WORDS.forEach((word) => intentWords.add(word));
  }
  if (/\b(gracias|genial|perfecto)\b/.test(raw)) {
    if (only(tokens, new Set([...THANKS_WORDS, ...GREETING_WORDS]))) {
      return { text: "¡Con gusto! Si te quedas con otra duda, escríbela o toca una sugerencia.", chips: here };
    }
    THANKS_WORDS.forEach((word) => intentWords.add(word));
  }
  const content = (): string[] => tokens.filter((token) => !intentWords.has(token));

  if (/\b(me perdi|perdido|perdida|no se que hacer|ayuda|ayudame|auxilio|no entiendo)\b/.test(raw)) {
    if (only(content(), LOST_WORDS)) {
      return {
        text:
          `No te preocupes, vamos paso a paso. Estás en: ${topic.heading}.\n${topic.purpose}\n` +
          `Aquí puedes:\n${bullets(topic.canDo)}\nElige una sugerencia para empezar.`,
        chips: here,
      };
    }
    LOST_WORDS.forEach((word) => intentWords.add(word));
  }
  let purposeAsked = false;
  if (/\b(para que sirve|que es esta|donde estoy)\b/.test(raw)) {
    if (only(content(), PURPOSE_WORDS)) {
      return {
        text: `${topic.heading}.\n${topic.purpose}\n\nAquí puedes:\n${bullets(topic.canDo)}`,
        chips: pickChips(getInitialChips(screenId), PURPOSE_CHIP),
      };
    }
    PURPOSE_WORDS.forEach((word) => intentWords.add(word));
    purposeAsked = true;
  }
  if (/\b(errores|problemas) (comunes|frecuentes)\b/.test(raw) || /^que errores\b/.test(raw)) {
    if (only(content(), MISTAKE_WORDS)) {
      const list = topic.mistakes.map((m) => `- ${m.problem}\n  Qué hacer: ${m.fix}`).join("\n");
      return { text: `Errores comunes en esta pantalla:\n${list}`, chips: pickChips(getInitialChips(screenId), ERRORS_CHIP) };
    }
    MISTAKE_WORDS.forEach((word) => intentWords.add(word));
  }
  if (/\b(que mas|otras cosas|otras pantallas|en el sistema)\b/.test(raw)) {
    if (only(content(), MORE_WORDS)) return otherScreens(screenId);
    MORE_WORDS.forEach((word) => intentWords.add(word));
  }

  const query = content();
  const groups = query.map(toGroup);
  const glossaryBoost =
    purposeAsked || /\b(que es|que son|significa|significan|quiere decir|definicion)\b/.test(raw);
  const normalized = query.join(" ");
  let best: { entry: Entry; score: number; coverage: number; missedStrict: number } | null = null;
  for (const entry of getKnowledgeBase()) {
    const scored = scoreEntry(entry, groups, normalized, glossaryBoost);
    let score = scored.score;
    if (entry.screen === screenId) score *= 1.5;
    if (score > (best?.score ?? 0)) best = { entry, score, coverage: scored.coverage, missedStrict: scored.missedStrict };
  }
  if (!best || best.score < MIN_SCORE) return fallback(screenId, question);
  if (groups.length >= 2 && best.coverage < MIN_COVERAGE) return fallback(screenId, question);
  // With exactly two meaningful words both must match (a generic one may be skipped only if the other matches).
  if (groups.length === 2 && best.missedStrict > 0) return fallback(screenId, question);
  return answerWithEntry(best.entry, screenId, question);
}
