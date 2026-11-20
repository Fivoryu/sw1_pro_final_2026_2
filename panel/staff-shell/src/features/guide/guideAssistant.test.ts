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
