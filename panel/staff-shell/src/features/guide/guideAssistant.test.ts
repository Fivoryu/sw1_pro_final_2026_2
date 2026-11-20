import { describe, expect, it } from "vitest";
import { GUIDE_SCREEN_IDS, GUIDE_TOPICS } from "./guideContent";
import { answerQuestion, getGreeting, getInitialChips, normalizeText } from "./guideAssistant";

describe("normalizeText", () => {
  it("lowercases, strips accents, punctuation and stopwords", () => {
    expect(normalizeText("¿Cómo ENTRO al sistema?!")).toEqual(["entro", "sistema"]);
  });
});

describe("initial chips and greeting", () => {
  it.each(GUIDE_SCREEN_IDS)("%s has at least 3 context chips and a Spanish greeting", (id) => {
    const chips = getInitialChips(id);
    expect(chips.length).toBeGreaterThanOrEqual(3);
    expect(new Set(chips).size).toBe(chips.length);
    expect(chips).toContain("¿Para qué sirve esta pantalla?");
    for (const w of GUIDE_TOPICS[id].walkthroughs.slice(0, 4)) expect(chips).toContain(w.title);
    const greeting = getGreeting(id);
    expect(greeting).toContain("¡Hola!");
    expect(greeting).toContain(GUIDE_TOPICS[id].heading);
  });
});

describe("answerQuestion", () => {
  it("answers a login problem with the matching walkthrough", () => {
    const r = answerQuestion("no puedo entrar", "login");
    expect(r.text).toContain("1.");
    expect(r.text).toContain("Escribe tu correo");
    expect(r.chips.length).toBeGreaterThanOrEqual(2);
    expect(r.chips.length).toBeLessThanOrEqual(4);
  });

  it("answers a common mistake", () => {
    const r = answerQuestion("me sale un error de credenciales", "login");
    expect(r.text).toContain("Revisa el correo y la contraseña");
  });

  it("tolerates missing accents and light typos", () => {
    const r = answerQuestion("COMO ACTIBO MI CUENTA CON LA INVITACION", "invitation-acceptance");
    expect(r.text).toContain("Abre el enlace del correo");
  });

  it("explains a glossary term", () => {
    const r = answerQuestion("¿Qué significa autenticadora?", "login");
    expect(r.text.toLowerCase()).toContain("aplicación autenticadora");
    expect(r.chips.length).toBeGreaterThanOrEqual(2);
  });

  it("says where another screen lives", () => {
    const r = answerQuestion("quiero cambiar el tipo de cambio", "login");
    expect(r.text).toContain(GUIDE_TOPICS["exchange-rates"].heading);
    expect(r.text).toMatch(/pantalla/);
  });

  it("handles purpose, errors, lost and thanks intents", () => {
    expect(answerQuestion("¿Para qué sirve esta pantalla?", "login").text).toContain(GUIDE_TOPICS.login.purpose);
    expect(answerQuestion("¿Qué errores son comunes?", "login").text).toContain("No pudimos validar");
    const lost = answerQuestion("me perdí, no sé qué hacer", "login");
    expect(lost.text).toContain(GUIDE_TOPICS.login.heading);
    expect(lost.chips.length).toBeGreaterThanOrEqual(3);
    expect(answerQuestion("gracias", "login").text).toMatch(/Con gusto/);
    expect(answerQuestion("hola", "login").text).toContain("¡Hola!");
  });

  it("lists other things to do in the system", () => {
    const r = answerQuestion("¿Qué más puedo hacer en el sistema?", "login");
    expect(r.text).toContain(GUIDE_TOPICS["exchange-rates"].heading);
  });

  it("falls back honestly on nonsense with chips and topics", () => {
    const r = answerQuestion("xqzvw plmk", "login");
    expect(r.text).toContain("No estoy seguro");
    expect(r.text).toContain(GUIDE_TOPICS.login.walkthroughs[0].title);
    expect(r.chips.length).toBeGreaterThanOrEqual(3);
  });

  it("answers every walkthrough title of every screen with that walkthrough", () => {
    for (const id of GUIDE_SCREEN_IDS) {
      for (const w of GUIDE_TOPICS[id].walkthroughs) {
        const r = answerQuestion(w.title, id);
        expect(r.text, `${id}: ${w.title}`).toContain(w.steps[0].title);
      }
    }
  });
});

describe("answerQuestion: intents do not hijack real questions (J4)", () => {
  it("answers the question after a greeting prefix", () => {
    const r = answerQuestion("hola, ¿cómo hago para entrar?", "login");
    expect(r.text).toContain("Escribe tu correo");
    expect(r.text).not.toContain("Soy la guía");
  });

  it("does not treat 'ayuda para X' as getting lost", () => {
    const r = answerQuestion("necesito ayuda para publicar", "welcome-agency-admin");
    expect(r.text).not.toContain("No te preocupes");
    expect(r.text.toLowerCase()).toContain("publica");
  });

  it("answers glossary questions phrased with intent words", () => {
    expect(answerQuestion("¿para qué sirve el tipo de cambio?", "login").text).toContain("Tipo de cambio:");
    expect(answerQuestion("no entiendo qué es tipo de cambio", "login").text).toContain("Tipo de cambio:");
  });

  it("answers 'en el sistema' questions instead of listing screens", () => {
    const r = answerQuestion("cómo entro en el sistema", "login");
    expect(r.text).toContain("Escribe tu correo");
    expect(r.text).not.toContain("Además de esta pantalla");
  });

  it("answers the question after thanks", () => {
    const r = answerQuestion("gracias, y cómo entro", "login");
    expect(r.text).toContain("Escribe tu correo");
    expect(r.text).not.toMatch(/^¡Con gusto/);
  });

  it("still handles bare intents", () => {
    expect(answerQuestion("muchas gracias", "login").text).toMatch(/Con gusto/);
    expect(answerQuestion("hola buenas", "login").text).toContain("¡Hola!");
    expect(answerQuestion("necesito ayuda", "login").text).toContain("No te preocupes");
  });
});

describe("answerQuestion: typos, synonyms and sessions (J5)", () => {
  it("tolerates a one-letter typo in a long word", () => {
    expect(answerQuestion("¿qué significa aitenticadora?", "login").text.toLowerCase()).toContain("aplicación autenticadora");
  });

  it("does not apply fuzzy matching to short words", () => {
    expect(answerQuestion("xyz abc", "login").text).toContain("No estoy seguro");
  });

  it.each(["cómo ingreso", "quiero acceder", "cómo me logueo", "cómo inicio sesión"])("%s resolves to login", (q) => {
    expect(answerQuestion(q, "login").text).toContain("Escribe tu correo");
  });

  it("resolves 'cómo cierro sesión' to the logout walkthrough, not login", () => {
    for (const id of ["welcome-platform-admin", "welcome-agency-admin", "welcome-agent"] as const) {
      const r = answerQuestion("cómo cierro sesión", id);
      expect(r.text, id).toContain("Cerrar sesión");
      expect(r.text, id).not.toContain("Escribe tu correo");
    }
    expect(answerQuestion("cómo cierro sesión", "login").text).toContain("Cerrar sesión");
  });

  it("resolves 'quiero eliminar una publicación' and 'cómo salgo' sensibly", () => {
    expect(answerQuestion("cómo salgo", "welcome-agent").text).toContain("Cerrar sesión");
  });
});

describe("answerQuestion: partial matches fall back (J8)", () => {
  it("does not answer 'borrar un inmueble' with an unrelated walkthrough", () => {
    const r = answerQuestion("quiero borrar un inmueble", "listing-review-queue");
    expect(r.text).toContain("No estoy seguro");
  });

  it("still answers when the words are covered", () => {
    expect(answerQuestion("abrir un inmueble para revisarlo", "listing-review-queue").text).toContain("1.");
  });
});

