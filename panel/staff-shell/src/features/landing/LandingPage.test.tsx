import { render, screen } from "@testing-library/react";
import userEvent from "@testing-library/user-event";
import { describe, expect, it } from "vitest";
import { LandingPage } from "./LandingPage";

describe("landing pricing section", () => {
  it("renders the three plans with monthly prices by default", () => {
    render(<LandingPage />);

    expect(screen.getByRole("heading", { name: "Básico" })).toBeVisible();
    expect(screen.getByRole("heading", { name: "Profesional" })).toBeVisible();
    expect(screen.getByRole("heading", { name: "Corporativo" })).toBeVisible();

    expect(screen.getByText("$29")).toBeVisible();
    expect(screen.getByText("$79")).toBeVisible();
    expect(screen.getByText("$199")).toBeVisible();
  });

  it("shows the annual prices with the 15% discount after switching billing", async () => {
    render(<LandingPage />);

    await userEvent.click(screen.getByRole("button", { name: /Anual/ }));

    expect(screen.getByText("$25")).toBeVisible();
    expect(screen.getByText("$67")).toBeVisible();
    expect(screen.getByText("$169")).toBeVisible();
    expect(
      screen.getByRole("button", { name: /15% de descuento/ }),
    ).toHaveAttribute("aria-pressed", "true");

    expect(screen.getByText(/\$300 al año/)).toBeVisible();
    expect(screen.getByText(/\$804 al año/)).toBeVisible();
    expect(screen.getByText(/\$2028 al año/)).toBeVisible();
    expect(screen.getByText("Ahorrás $48 al año")).toBeVisible();
    expect(screen.getByText("Ahorrás $144 al año")).toBeVisible();
    expect(screen.getByText("Ahorrás $360 al año")).toBeVisible();

    await userEvent.click(screen.getByRole("button", { name: "Mensual" }));
    expect(screen.getAllByText("Facturación mensual")).toHaveLength(3);
    expect(screen.queryByText(/\$300 al año/)).not.toBeInTheDocument();
    expect(screen.queryByText(/Ahorrás \$48/)).not.toBeInTheDocument();
  });

  it("highlights the Professional plan as the popular choice", () => {
    render(<LandingPage />);

    expect(screen.getByText("Más elegido")).toBeVisible();
  });
});
