import { render, screen, within } from "@testing-library/react";
import userEvent from "@testing-library/user-event";
import { describe, expect, it, vi } from "vitest";
import { StaffLoginShell } from "../auth/StaffLoginShell";
import { LandingPage } from "../landing/LandingPage";
import { ContextualGuide } from "./ContextualGuide";
import { GUIDE_SCREEN_IDS } from "./guideContent";

describe("ContextualGuide sections", () => {
  it("shows purpose, step by step, common mistakes and glossary, and closes with Escape", async () => {
    const user = userEvent.setup();
    render(<ContextualGuide screenId="exchange-rates" />);
    await user.click(screen.getByRole("button", { name: "Guía" }));
    const panel = screen.getByRole("complementary", { name: "Guía" });
    await user.click(within(panel).getByRole("button", { name: "Ver guía completa" }));
    expect(within(panel).getByRole("tab", { name: "Para qué sirve" })).toHaveAttribute("aria-selected", "true");
    await user.click(within(panel).getByRole("tab", { name: "Paso a paso" }));
    expect(within(panel).getAllByRole("listitem").length).toBeGreaterThanOrEqual(3);
    await user.click(within(panel).getByRole("tab", { name: "Errores comunes" }));
    expect(panel).toHaveTextContent("Qué hacer");
    await user.click(within(panel).getByRole("tab", { name: "Glosario" }));
    expect(panel).toHaveTextContent("Tipo de cambio");
    await user.keyboard("{Escape}");
    expect(screen.queryByRole("complementary", { name: "Guía" })).toBeNull();
  });

  it("renders every registered screen without errors", async () => {
    const user = userEvent.setup();
    for (const id of GUIDE_SCREEN_IDS) {
      const { unmount } = render(<ContextualGuide screenId={id} />);
      await user.click(screen.getByRole("button", { name: "Guía" }));
      expect(screen.getByRole("complementary", { name: "Guía" })).toBeVisible();
      unmount();
    }
  });
});

describe("guide integrated in screens", () => {
  it("opens on the login screen without submitting", async () => {
    const user = userEvent.setup();
    const onAuthenticated = vi.fn();
    const fetchSpy = vi.spyOn(globalThis, "fetch");
    render(<StaffLoginShell onAuthenticated={onAuthenticated} />);
    await user.click(screen.getByRole("button", { name: "Guía" }));
    expect(screen.getByRole("complementary", { name: "Guía" })).toHaveTextContent("correo");
    expect(fetchSpy).not.toHaveBeenCalled();
    expect(onAuthenticated).not.toHaveBeenCalled();
    fetchSpy.mockRestore();
  });

  it("opens on the landing page", async () => {
    const user = userEvent.setup();
    render(<LandingPage />);
    await user.click(screen.getByRole("button", { name: "Guía" }));
    expect(screen.getByRole("complementary", { name: "Guía" })).toBeVisible();
  });
});

describe("ContextualGuide chat", () => {
  it("greets, shows chips, answers a chip and a typed question without running screen actions", async () => {
    const user = userEvent.setup();
    const fetchSpy = vi.spyOn(globalThis, "fetch");
    const onAuthenticated = vi.fn();
    render(<StaffLoginShell onAuthenticated={onAuthenticated} />);
    await user.click(screen.getByRole("button", { name: "Guía" }));
    const panel = screen.getByRole("complementary", { name: "Guía" });
    const log = within(panel).getByRole("log");
    expect(log).toHaveAttribute("aria-live", "polite");
    expect(log).toHaveTextContent("¡Hola!");
    await user.click(within(panel).getByRole("button", { name: "¿Para qué sirve esta pantalla?" }));
    expect(log).toHaveTextContent("segura");
    expect(within(panel).getAllByRole("button", { name: /¿Qué errores son comunes\?/ }).length).toBe(1);
    const input = within(panel).getByRole("textbox", { name: "Escribe tu pregunta" });
    await user.type(input, "no puedo entrar{Enter}");
    expect(input).toHaveValue("");
    expect(log).toHaveTextContent("no puedo entrar");
    expect(log).toHaveTextContent("Escribe tu correo");
    expect(within(panel).getAllByRole("button").length).toBeGreaterThan(4);
    expect(fetchSpy).not.toHaveBeenCalled();
    expect(onAuthenticated).not.toHaveBeenCalled();
    fetchSpy.mockRestore();
  });

  it("sends with the button, closes with Escape and returns focus to the toggle", async () => {
    const user = userEvent.setup();
    render(<ContextualGuide screenId="exchange-rates" />);
    await user.click(screen.getByRole("button", { name: "Guía" }));
    const panel = screen.getByRole("complementary", { name: "Guía" });
    await user.type(within(panel).getByRole("textbox", { name: "Escribe tu pregunta" }), "qué es tipo de cambio");
    await user.click(within(panel).getByRole("button", { name: "Enviar" }));
    expect(within(panel).getByRole("log")).toHaveTextContent("Tipo de cambio");
    await user.keyboard("{Escape}");
    expect(screen.queryByRole("complementary", { name: "Guía" })).toBeNull();
    expect(screen.getByRole("button", { name: "Guía" })).toHaveFocus();
  });
});
