import { act, render, screen, waitFor, within } from "@testing-library/react";
import userEvent from "@testing-library/user-event";
import { afterEach, beforeEach, describe, expect, it, vi } from "vitest";
import { listAgencyAgents } from "../../application/listingAgentsApi";
import {
  blockCustomer,
  listBlockedCustomers,
  listConversations,
  listMessages,
  listReports,
  reassignConversation,
  reportCustomer,
  sendMessage,
  StaffChatApiError,
  unblockCustomer,
  type StaffConversation,
  type StaffMessage,
} from "../../application/staffChatApi";
import { ChatInbox, INBOX_POLL_MS } from "./ChatInbox";
import { ChatReports } from "./ChatReports";
import { MESSAGE_POLL_MS } from "./ConversationView";

vi.mock("../../application/staffChatApi", async (importOriginal) => {
  const actual = await importOriginal<typeof import("../../application/staffChatApi")>();
  return {
    ...actual,
    listConversations: vi.fn(),
    listMessages: vi.fn(),
    sendMessage: vi.fn(),
    reassignConversation: vi.fn(),
    reportCustomer: vi.fn(),
    listReports: vi.fn(),
    listBlockedCustomers: vi.fn(),
    blockCustomer: vi.fn(),
    unblockCustomer: vi.fn(),
  };
});

vi.mock("../../application/listingAgentsApi", async (importOriginal) => {
  const actual = await importOriginal<typeof import("../../application/listingAgentsApi")>();
  return { ...actual, listAgencyAgents: vi.fn() };
});

function conversation(overrides: Partial<StaffConversation> = {}): StaffConversation {
  return {
    id: "c1",
    listing_id: "listing-1",
    customer_email: "cliente@example.test",
    status: "unclaimed",
    mine: false,
    read_only: false,
    needs_admin: false,
    overdue: false,
    created_at: "2026-11-01T10:00:00Z",
    last_message_at: "2026-11-01T10:05:00Z",
    ...overrides,
  };
}

function message(overrides: Partial<StaffMessage> = {}): StaffMessage {
  return {
    id: 1,
    sender: "customer",
    mine: false,
    body: "Hola, ¿sigue disponible?",
    created_at: "2026-11-01T10:00:00Z",
    ...overrides,
  };
}

beforeEach(() => {
  vi.mocked(listConversations).mockReset().mockResolvedValue([conversation()]);
  vi.mocked(listMessages)
    .mockReset()
    .mockResolvedValue({ messages: [message()], read_only: false });
  vi.mocked(sendMessage).mockReset();
  vi.mocked(reassignConversation).mockReset().mockResolvedValue(undefined);
  vi.mocked(reportCustomer).mockReset().mockResolvedValue(undefined);
  vi.mocked(listReports).mockReset().mockResolvedValue([]);
  vi.mocked(listBlockedCustomers).mockReset().mockResolvedValue([]);
  vi.mocked(blockCustomer).mockReset().mockResolvedValue(undefined);
  vi.mocked(unblockCustomer).mockReset().mockResolvedValue(undefined);
  vi.mocked(listAgencyAgents).mockReset().mockResolvedValue([
    { id: "a1", email: "uno@example.test", active: true },
    { id: "a2", email: "dos@example.test", active: false },
  ]);
});

afterEach(() => {
  vi.useRealTimers();
});

describe("ChatInbox", () => {
  it("lists conversations with customer, listing and status badges", async () => {
    vi.mocked(listConversations).mockResolvedValue([
      conversation(),
      conversation({
        id: "c2",
        customer_email: "otro@example.test",
        status: "claimed",
        mine: true,
        read_only: true,
        needs_admin: true,
        overdue: true,
      }),
    ]);

    render(<ChatInbox accessToken="staff-access" isAgencyAdmin={false} />);

    const list = await screen.findByRole("list", { name: "Conversaciones" });
    const [first, second] = within(list).getAllByRole("listitem");
    expect(first).toHaveTextContent("cliente@example.test");
    expect(first).toHaveTextContent("Inmueble listing-1");
    expect(first).toHaveTextContent("Sin atender");
    expect(second).toHaveTextContent("Atendida por ti");
    expect(second).toHaveTextContent("Solo lectura");
    expect(second).toHaveTextContent("Requiere administrador");
    expect(second).toHaveTextContent("Sin respuesta");
    expect(listConversations).toHaveBeenCalledWith("staff-access");
  });

  it("does not show the owning agent to a plain agent", async () => {
    vi.mocked(listConversations).mockResolvedValue([
      conversation({ agent_email: "dueno@example.test" }),
    ]);

    render(<ChatInbox accessToken="staff-access" isAgencyAdmin={false} />);

    await screen.findByRole("list", { name: "Conversaciones" });
    expect(screen.queryByText(/dueno@example\.test/)).not.toBeInTheDocument();
    expect(listBlockedCustomers).not.toHaveBeenCalled();
  });

  it("shows the owning agent and the reports panel to the agency admin", async () => {
    vi.mocked(listConversations).mockResolvedValue([
      conversation({ status: "claimed", agent_email: "dueno@example.test" }),
    ]);

    render(<ChatInbox accessToken="staff-access" isAgencyAdmin />);

    expect(await screen.findByText(/Agente dueno@example\.test/)).toBeVisible();
    expect(await screen.findByText("No hay reportes.")).toBeVisible();
    expect(listBlockedCustomers).toHaveBeenCalled();
  });

  it("shows an error with retry when the inbox fails to load", async () => {
    const user = userEvent.setup();
    vi.mocked(listConversations).mockRejectedValueOnce(new Error("boom"));

    render(<ChatInbox accessToken="staff-access" isAgencyAdmin={false} />);

    expect(await screen.findByRole("alert")).toHaveTextContent("boom");
    await user.click(screen.getByRole("button", { name: "Reintentar" }));
    expect(await screen.findByRole("list", { name: "Conversaciones" })).toBeVisible();
  });

  it("polls the inbox every 15 seconds", async () => {
    vi.useFakeTimers();
    render(<ChatInbox accessToken="staff-access" isAgencyAdmin={false} />);
    await act(async () => {
      await vi.advanceTimersByTimeAsync(0);
    });
    expect(listConversations).toHaveBeenCalledTimes(1);

    await act(async () => {
      await vi.advanceTimersByTimeAsync(INBOX_POLL_MS);
    });

    expect(listConversations).toHaveBeenCalledTimes(2);
  });
});

describe("conversation view", () => {
  async function openFirst(isAgencyAdmin: boolean) {
    const user = userEvent.setup();
    render(<ChatInbox accessToken="staff-access" isAgencyAdmin={isAgencyAdmin} />);
    await user.click(await screen.findByRole("button", { name: /cliente@example\.test/ }));
    await screen.findByText("Hola, ¿sigue disponible?");
    return user;
  }

  it("loads messages from the start and sends a reply", async () => {
    vi.mocked(sendMessage).mockResolvedValue(
      message({ id: 2, sender: "agent", mine: true, body: "Sí, disponible" }),
    );
    const user = await openFirst(false);
    expect(listMessages).toHaveBeenCalledWith("staff-access", "c1", 0);

    await user.type(screen.getByLabelText("Mensaje"), "Sí, disponible");
    await user.click(screen.getByRole("button", { name: "Enviar" }));

    expect(sendMessage).toHaveBeenCalledWith("staff-access", "c1", "Sí, disponible");
    expect(await screen.findByText("Sí, disponible")).toBeVisible();
    expect(screen.getByLabelText("Mensaje")).toHaveValue("");
  });

  it("polls for messages after the last id every 3 seconds without duplicating", async () => {
    vi.useFakeTimers();
    render(<ChatInbox accessToken="staff-access" isAgencyAdmin={false} />);
    await act(async () => {
      await vi.advanceTimersByTimeAsync(0);
    });
    await act(async () => {
      screen.getByRole("button", { name: /cliente@example\.test/ }).click();
      await vi.advanceTimersByTimeAsync(0);
    });
    expect(listMessages).toHaveBeenLastCalledWith("staff-access", "c1", 0);

    vi.mocked(listMessages).mockResolvedValue({
      messages: [message({ id: 1 }), message({ id: 2, body: "Nuevo mensaje" })],
      read_only: false,
    });
    await act(async () => {
      await vi.advanceTimersByTimeAsync(MESSAGE_POLL_MS);
    });
    expect(listMessages).toHaveBeenLastCalledWith("staff-access", "c1", 1);
    expect(screen.getByText("Nuevo mensaje")).toBeVisible();

    vi.mocked(listMessages).mockResolvedValue({ messages: [message({ id: 2 })], read_only: false });
    await act(async () => {
      await vi.advanceTimersByTimeAsync(MESSAGE_POLL_MS);
    });
    expect(listMessages).toHaveBeenLastCalledWith("staff-access", "c1", 2);
    expect(screen.getAllByText("Nuevo mensaje")).toHaveLength(1);
  });

  it("on 409 Conversation already taken shows a notice and refreshes the inbox", async () => {
    vi.mocked(sendMessage).mockRejectedValue(
      new StaffChatApiError(409, "Conversation already taken", "conflict"),
    );
    const user = await openFirst(false);
    const callsBefore = vi.mocked(listConversations).mock.calls.length;

    await user.type(screen.getByLabelText("Mensaje"), "Yo respondo");
    await user.click(screen.getByRole("button", { name: "Enviar" }));

    expect(await screen.findByRole("alert")).toHaveTextContent(
      "Otro agente ya tomó esta conversación",
    );
    expect(screen.queryByLabelText("Mensaje")).not.toBeInTheDocument();
    await waitFor(() => {
      expect(vi.mocked(listConversations).mock.calls.length).toBeGreaterThan(callsBefore);
    });
  });

  it("shows other send errors in place and keeps the draft", async () => {
    vi.mocked(sendMessage).mockRejectedValue(
      new StaffChatApiError(409, "Conversation is read-only", "conflict"),
    );
    const user = await openFirst(false);

    await user.type(screen.getByLabelText("Mensaje"), "Texto");
    await user.click(screen.getByRole("button", { name: "Enviar" }));

    expect(await screen.findByRole("alert")).toHaveTextContent("Conversation is read-only");
    expect(screen.getByLabelText("Mensaje")).toHaveValue("Texto");
  });

  it("disables the input when the conversation is read-only", async () => {
    vi.mocked(listConversations).mockResolvedValue([conversation({ read_only: true })]);
    await openFirst(false);

    expect(screen.getByLabelText("Mensaje")).toBeDisabled();
    expect(screen.getByRole("button", { name: "Enviar" })).toBeDisabled();
    expect(screen.getByText("Esta conversación es de solo lectura.")).toBeVisible();
  });

  it("disables the input when the message page reports read-only", async () => {
    vi.mocked(listMessages).mockResolvedValue({ messages: [message()], read_only: true });
    await openFirst(false);

    await waitFor(() => expect(screen.getByLabelText("Mensaje")).toBeDisabled());
  });

  it("hides the real author from a plain agent", async () => {
    vi.mocked(listMessages).mockResolvedValue({
      messages: [message({ id: 2, sender: "agent", author_email: "secreto@example.test" })],
      read_only: false,
    });
    const user = userEvent.setup();
    render(<ChatInbox accessToken="staff-access" isAgencyAdmin={false} />);
    await user.click(await screen.findByRole("button", { name: /cliente@example\.test/ }));

    await screen.findByRole("list", { name: "Mensajes" });
    expect(screen.queryByText(/secreto@example\.test/)).not.toBeInTheDocument();
    expect(screen.queryByRole("form", { name: "Reasignar conversación" })).not.toBeInTheDocument();
  });

  it("shows the author of each message and the owner to the agency admin", async () => {
    vi.mocked(listConversations).mockResolvedValue([
      conversation({ status: "claimed", agent_email: "dueno@example.test" }),
    ]);
    vi.mocked(listMessages).mockResolvedValue({
      messages: [
        message({ id: 2, sender: "agent", author_email: "autor@example.test", body: "Respuesta" }),
      ],
      read_only: false,
    });
    const user = userEvent.setup();
    render(<ChatInbox accessToken="staff-access" isAgencyAdmin />);
    await user.click(await screen.findByRole("button", { name: /cliente@example\.test/ }));

    const messages = await screen.findByRole("list", { name: "Mensajes" });
    expect(within(messages).getByText(/autor@example\.test/)).toBeVisible();
    expect(screen.getByText("Atiende: dueno@example.test")).toBeVisible();
  });

  it("lets the agency admin reassign automatically or to a chosen active agent", async () => {
    const user = await openFirst(true);
    const form = await screen.findByRole("form", { name: "Reasignar conversación" });
    expect(await within(form).findByRole("option", { name: "uno@example.test" })).toBeVisible();
    expect(within(form).queryByRole("option", { name: "dos@example.test" })).not.toBeInTheDocument();

    await user.click(within(form).getByRole("button", { name: "Reasignar" }));
    expect(reassignConversation).toHaveBeenLastCalledWith("staff-access", "c1", undefined);

    await user.selectOptions(within(form).getByLabelText("Reasignar a"), "a1");
    await user.click(within(form).getByRole("button", { name: "Reasignar" }));
    expect(reassignConversation).toHaveBeenLastCalledWith("staff-access", "c1", "a1");
    expect(await within(form).findAllByText("Conversación reasignada.")).not.toHaveLength(0);
  });

  it("lets staff report the customer", async () => {
    const user = await openFirst(false);

    await user.type(screen.getByLabelText("Motivo del reporte"), "Insultos");
    await user.click(screen.getByRole("button", { name: "Reportar cliente" }));

    expect(reportCustomer).toHaveBeenCalledWith("staff-access", "c1", "Insultos");
    expect(await screen.findByText("Reporte enviado.")).toBeVisible();
  });

  it("offers blocking only to the admin and only when the API gives the customer id", async () => {
    vi.mocked(listConversations).mockResolvedValue([conversation({ customer_id: "u1" })]);
    const user = await openFirst(true);

    await user.click(screen.getByRole("button", { name: "Bloquear cliente" }));
    expect(blockCustomer).toHaveBeenCalledWith("staff-access", "u1");
    expect(await screen.findByText("Cliente bloqueado.")).toBeVisible();
  });

  it("hides blocking from agents and when no customer id is returned", async () => {
    vi.mocked(listConversations).mockResolvedValue([conversation({ customer_id: "u1" })]);
    await openFirst(false);
    expect(screen.queryByRole("button", { name: "Bloquear cliente" })).not.toBeInTheDocument();
  });
});

describe("ChatReports", () => {
  it("lists reports with the authors for the platform admin without blocks", async () => {
    vi.mocked(listReports).mockResolvedValue([
      {
        id: "r1",
        conversation_id: "c1",
        listing_id: "listing-1",
        agency_id: "agency-1",
        reporter_role: "customer",
        reason: "Trato inadecuado",
        created_at: "2026-11-02T10:00:00Z",
        agent_ids: ["a1"],
      },
    ]);

    render(<ChatReports accessToken="staff-access" showBlocks={false} />);

    const list = await screen.findByRole("list", { name: "Reportes" });
    expect(list).toHaveTextContent("Trato inadecuado");
    expect(list).toHaveTextContent("Agentes: a1");
    expect(listBlockedCustomers).not.toHaveBeenCalled();
    expect(screen.queryByText("Clientes bloqueados")).not.toBeInTheDocument();
  });

  it("lists blocked customers and unblocks one", async () => {
    vi.mocked(listBlockedCustomers)
      .mockResolvedValueOnce([{ customer_id: "u1", created_at: "2026-11-02T10:00:00Z" }])
      .mockResolvedValueOnce([]);
    const user = userEvent.setup();

    render(<ChatReports accessToken="staff-access" showBlocks />);

    const list = await screen.findByRole("list", { name: "Clientes bloqueados" });
    expect(list).toHaveTextContent("Cliente u1");
    await user.click(within(list).getByRole("button", { name: "Desbloquear" }));

    expect(unblockCustomer).toHaveBeenCalledWith("staff-access", "u1");
    expect(await screen.findByText("No hay clientes bloqueados.")).toBeVisible();
  });

  it("shows an error when reports fail to load", async () => {
    vi.mocked(listReports).mockRejectedValue(new StaffChatApiError(403, "Admin role is required"));

    render(<ChatReports accessToken="staff-access" showBlocks={false} />);

    expect(await screen.findByRole("alert")).toHaveTextContent("Admin role is required");
  });
});
