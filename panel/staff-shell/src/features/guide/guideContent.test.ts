import { describe, expect, it } from "vitest";
import { GLOSSARY, GUIDE_SCREEN_IDS, GUIDE_TOPICS } from "./guideContent";

const DENYLIST = [
  /\bNext\b/,
  /Click here/i,
  /\bSubmit\b/,
  /\bCancel\b/,
  /\bLoading\b/,
  /\bSave\b/,
  /\bBack\b/,
  /\bLogin\b/,
  /\bSign in\b/i,
  /\bPlease\b/,
  /\bDashboard\b/,
];

const EXPECTED = [
  "login", "invitation-acceptance", "landing", "welcome-platform-admin",
  "welcome-agency-admin", "welcome-agent", "agency-dashboard", "agency-invitations",
  "listing-review-queue", "listing-detail", "scene-editor", "capture-drafts",
  "furniture-review", "exchange-rates", "card-payments", "chat-inbox",
  "chat-conversation", "chat-reports", "notifications", "agency-reviews",
  "review-reports", "scene-viewer",
];

function allText(id: (typeof GUIDE_SCREEN_IDS)[number]): string {
  const t = GUIDE_TOPICS[id];
  return [
    t.heading, t.purpose, ...t.canDo,
    ...t.walkthroughs.flatMap((w) => [w.title, ...w.steps.flatMap((s) => [s.title, s.detail])]),
    ...t.mistakes.flatMap((m) => [m.problem, m.fix]),
    ...t.glossary.map((k) => `${GLOSSARY[k].term} ${GLOSSARY[k].meaning}`),
  ].join(" ");
}

describe("guide content completeness", () => {
  it("registers every screen of the staff panel", () => {
    expect([...GUIDE_SCREEN_IDS].sort()).toEqual([...EXPECTED].sort());
  });

  it.each(EXPECTED)("%s has purpose, walkthroughs, mistakes and glossary", (id) => {
    const t = GUIDE_TOPICS[id as keyof typeof GUIDE_TOPICS];
    expect(t.purpose.trim().length).toBeGreaterThan(20);
    expect(t.canDo.length).toBeGreaterThanOrEqual(1);
    expect(t.walkthroughs.length).toBeGreaterThanOrEqual(1);
    for (const w of t.walkthroughs) expect(w.steps.length).toBeGreaterThanOrEqual(3);
    expect(t.mistakes.length).toBeGreaterThanOrEqual(1);
    expect(t.glossary.length).toBeGreaterThanOrEqual(1);
    for (const key of t.glossary) expect(GLOSSARY[key]?.meaning.length).toBeGreaterThan(10);
  });

  it("is written in Spanish without English interface words", () => {
    for (const id of GUIDE_SCREEN_IDS) {
      const text = allText(id);
      expect(text).toMatch(/[áéíóúñ]|\b(el|la|de|para|que)\b/);
      for (const word of DENYLIST) expect(text, `${id} ${word}`).not.toMatch(word);
    }
  });
});

describe("guide content accuracy against the panel (J2, J3, J9)", () => {
  it("platform admin guides do not mention the notification bell", () => {
    expect(allText("welcome-platform-admin")).not.toMatch(/campana/i);
  });

  it("the notifications guide is for agency staff and agency guides keep the bell", () => {
    expect(GUIDE_TOPICS.notifications.audience).toBe("Personal de inmobiliaria (administradores y agentes).");
    expect(allText("welcome-agent")).toMatch(/campana/i);
  });

  it("chat reports guide says only agency admins see the blocked clients list (R2-2)", () => {
    const text = allText("chat-reports");
    expect(text).toMatch(/Clientes bloqueados/);
    expect(text).toMatch(/Desbloquear/);
    expect(text).toMatch(/solo los administradores de (la )?inmobiliaria/i);
    expect(text).toMatch(/administrador de plataforma no/i);
  });

  it("platform admin welcome and chat guides do not claim the platform admin can unblock", () => {
    expect(allText("welcome-platform-admin")).not.toMatch(/Desbloquear/i);
    expect(allText("chat-conversation")).not.toMatch(/administrador de plataforma.{0,40}desbloque/i);
  });

  it("the agency admin chat inbox guide explains blocked clients and unblocking", () => {
    const t = GUIDE_TOPICS["chat-inbox"];
    expect(t.walkthroughs.some((w) => w.title.includes("Desbloquear"))).toBe(true);
    expect(allText("chat-inbox")).toMatch(/Clientes bloqueados/);
  });

  it("the blocked-by-mistake problem points to the agency admin, not the platform admin", () => {
    const m = GUIDE_TOPICS["chat-conversation"].mistakes.find((x) => x.problem.includes("Bloqueé"));
    expect(m?.fix).toMatch(/bandeja de chat/);
    expect(m?.fix).not.toMatch(/administrador de plataforma/);
  });

  it("welcome guides describe the left side menu, not a top menu", () => {
    for (const id of ["welcome-agency-admin", "welcome-agent"] as const) {
      expect(allText(id), id).not.toMatch(/menú de arriba/);
      expect(allText(id), id).toMatch(/menú lateral/);
    }
  });

  it("each welcome guide has a Cerrar sesión walkthrough", () => {
    for (const id of ["welcome-platform-admin", "welcome-agency-admin", "welcome-agent"] as const) {
      expect(GUIDE_TOPICS[id].walkthroughs.some((w) => w.title === "Cerrar sesión"), id).toBe(true);
    }
  });
});

