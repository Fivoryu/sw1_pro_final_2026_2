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
