import { useEffect, useId, useRef, useState } from "react";
import {
  getAgencyListing,
  listAgencyListings,
  listListingTransitions,
  StaffListingsApiError,
  transitionListing,
  type ListingReviewAction,
  type ListingTransition,
  type StaffListing,
} from "../../application/staffListingsApi";

type QueueTab = "pending" | "approved";

type LoadState<T> =
  | { kind: "loading" }
  | { kind: "ready"; value: T }
  | { kind: "error"; message: string };

interface AgencyReviewQueueProps {
  accessToken: string;
  agencyId: string;
}

const TABS: { id: QueueTab; label: string; empty: string }[] = [
  { id: "pending", label: "En revisión", empty: "No hay inmuebles esperando revisión." },
  { id: "approved", label: "Aprobados", empty: "No hay inmuebles aprobados." },
];

const ACTIONS: Record<
  ListingReviewAction,
  { label: string; confirmTitle: string; consequence: string; notice: string }
> = {
  approve: {
    label: "Aprobar",
    confirmTitle: "Confirmar aprobación",
    consequence:
      "El inmueble quedará aprobado, pero todavía no aparecerá en el catálogo hasta que lo publiques.",
    notice: "Inmueble aprobado.",
  },
  reject: {
    label: "Rechazar",
    confirmTitle: "Confirmar rechazo",
    consequence: "El agente verá el motivo y deberá editar el inmueble para enviarlo de nuevo.",
    notice: "Inmueble rechazado.",
  },
  publish: {
    label: "Publicar",
    confirmTitle: "Confirmar publicación",
    consequence: "El inmueble será visible para los clientes en el catálogo público.",
    notice: "Inmueble publicado.",
  },
  unpublish: {
    label: "Retirar del catálogo",
    confirmTitle: "Confirmar retiro",
    consequence: "Los clientes dejarán de ver el inmueble en el catálogo público.",
    notice: "Inmueble retirado del catálogo.",
  },
};

const HISTORY_LABELS: Record<ListingTransition["action"], string> = {
  create: "Creado",
  edit: "Editado",
  submit: "Enviado a revisión",
  approve: "Aprobado",
  reject: "Rechazado",
  publish: "Publicado",
  unpublish: "Retirado del catálogo",
};

const ROLE_LABELS: Record<string, string> = {
  agency_admin: "Administrador de inmobiliaria",
  agent: "Agente",
};

const STATUS_LABELS: Record<StaffListing["approval_status"], string> = {
  draft: "Borrador",
  pending: "En revisión",
  approved: "Aprobado",
  rejected: "Rechazado",
};

const SESSION_EXPIRED = "Tu sesión expiró. Cierra sesión y vuelve a ingresar.";
const CONFLICT =
  "El inmueble cambió de estado mientras lo revisabas. Se cargó su estado actual.";

/** Formats a server decimal string as COP without passing through floating point. */
export function formatCop(amount: string): string {
  const [integerPart, fractionPart = ""] = amount.trim().split(".");
  const grouped = integerPart.replace(/\B(?=(\d{3})+(?!\d))/g, ".");
  return `COP ${grouped},${fractionPart.padEnd(2, "0").slice(0, 2)}`;
}

function priceLabel(listing: StaffListing): string {
  const price = formatCop(listing.base_price);
  return listing.operation === "rent" ? `${price} por mes` : price;
}

function operationLabel(listing: StaffListing): string {
  return listing.operation === "rent" ? "Alquiler" : "Venta";
}

function roomsLabel(listing: StaffListing): string {
  const bedrooms = `${listing.bedrooms} ${listing.bedrooms === 1 ? "dormitorio" : "dormitorios"}`;
  const bathrooms = `${listing.bathrooms} ${listing.bathrooms === 1 ? "baño" : "baños"}`;
  return `${bedrooms} · ${bathrooms}`;
}

function formatDate(value: string): string {
  const date = new Date(value);
  return Number.isNaN(date.getTime())
    ? value
    : new Intl.DateTimeFormat("es-CO", { dateStyle: "medium", timeStyle: "short" }).format(
        date,
      );
}

function errorMessage(error: unknown, fallback: string): string {
  if (error instanceof StaffListingsApiError && error.status === 401) {
    return SESSION_EXPIRED;
  }
  if (error instanceof StaffListingsApiError && error.status === 403) {
    return "Tu cuenta no tiene permisos sobre los inmuebles de esta inmobiliaria.";
  }
  return fallback;
}

function availableActions(listing: StaffListing): ListingReviewAction[] {
  if (listing.approval_status === "pending") return ["approve", "reject"];
  if (listing.approval_status === "approved") {
    return [listing.is_published ? "unpublish" : "publish"];
  }
  return [];
}

export function AgencyReviewQueue({ accessToken, agencyId }: AgencyReviewQueueProps) {
  // The shell rotates the access token; keep the latest without refetching on rotation.
  const tokenRef = useRef(accessToken);
  tokenRef.current = accessToken;

  const [tab, setTab] = useState<QueueTab>("pending");
  const [listReload, setListReload] = useState(0);
  const [list, setList] = useState<LoadState<StaffListing[]>>({ kind: "loading" });
  const [selectedId, setSelectedId] = useState<string | null>(null);
  const [notice, setNotice] = useState<string | null>(null);

  useEffect(() => {
    let isCurrent = true;
    setList({ kind: "loading" });
    listAgencyListings(tokenRef.current, agencyId, { status: tab }).then(
      (result) => {
        if (isCurrent) setList({ kind: "ready", value: result.listings });
      },
      (error: unknown) => {
        if (isCurrent) {
          setList({
            kind: "error",
            message: errorMessage(error, "No se pudieron cargar los inmuebles."),
          });
        }
      },
    );
    return () => {
      isCurrent = false;
    };
  }, [agencyId, tab, listReload]);

  function selectTab(nextTab: QueueTab) {
    setNotice(null);
    setSelectedId(null);
    setTab(nextTab);
  }

  function handleCompleted(message: string) {
    setNotice(message);
    setSelectedId(null);
    setListReload((value) => value + 1);
  }

  const activeTab = TABS.find((candidate) => candidate.id === tab) ?? TABS[0];

  return (
    <section
      aria-labelledby="agency-review-queue-heading"
      className="protected-staff-review-queue"
    >
      <div className="protected-staff-review-queue__heading">
        <span className="protected-staff-review-queue__eyebrow">PUBLICACIONES DE LA INMOBILIARIA</span>
        <h2 id="agency-review-queue-heading">Cola de revisión</h2>
      </div>

      <div aria-label="Estado de los inmuebles" className="review-tabs" role="tablist">
        {TABS.map((candidate) => (
          <button
            aria-selected={candidate.id === tab}
            className="review-tabs__tab"
            key={candidate.id}
            onClick={() => selectTab(candidate.id)}
            role="tab"
            type="button"
          >
            {candidate.label}
          </button>
        ))}
      </div>

      {notice ? (
        <p className="review-notice" role="status">
          {notice}
        </p>
      ) : null}

      {selectedId ? (
        <ListingReviewDetail
          agencyId={agencyId}
          listingId={selectedId}
          onBack={() => setSelectedId(null)}
          onCompleted={handleCompleted}
          tokenRef={tokenRef}
        />
      ) : (
        <div role="tabpanel" aria-label={activeTab.label}>
          {list.kind === "loading" ? (
            <p aria-busy="true" className="review-queue__message">
              Cargando inmuebles…
            </p>
          ) : null}
          {list.kind === "error" ? (
            <div className="review-queue__message review-queue__message--error" role="alert">
              <p>{list.message}</p>
              <button
                className="review-button review-button--secondary"
                onClick={() => setListReload((value) => value + 1)}
                type="button"
              >
                Reintentar
              </button>
            </div>
          ) : null}
          {list.kind === "ready" && list.value.length === 0 ? (
            <div className="protected-staff-review-queue__empty-state">
              <p className="protected-staff-review-queue__empty">{activeTab.empty}</p>
            </div>
          ) : null}
          {list.kind === "ready" && list.value.length > 0 ? (
            <ul className="review-list">
              {list.value.map((item) => (
                <li key={item.listing_id}>
                  <button
                    aria-label={`Revisar ${operationLabel(item)} en ${item.city}, ${item.zone}`}
                    className="review-list__item"
                    onClick={() => {
                      setNotice(null);
                      setSelectedId(item.listing_id);
                    }}
                    type="button"
                  >
                    <span className="review-list__title">
                      {operationLabel(item)} · {item.city}, {item.zone}
                    </span>
                    <span className="review-list__price">{priceLabel(item)}</span>
                    <span className="review-list__meta">{roomsLabel(item)}</span>
                    {item.approval_status === "approved" ? (
                      <span className="review-list__badge">
                        {item.is_published ? "Publicado en el catálogo" : "Sin publicar"}
                      </span>
                    ) : null}
                  </button>
                </li>
              ))}
            </ul>
          ) : null}
        </div>
      )}
    </section>
  );
}

interface ListingReviewDetailProps {
  agencyId: string;
  listingId: string;
  onBack: () => void;
  onCompleted: (message: string) => void;
  tokenRef: { readonly current: string };
}

interface DetailValue {
  listing: StaffListing;
  history: ListingTransition[];
}

function ListingReviewDetail({
  agencyId,
  listingId,
  onBack,
  onCompleted,
  tokenRef,
}: ListingReviewDetailProps) {
  const [detailReload, setDetailReload] = useState(0);
  const [detail, setDetail] = useState<LoadState<DetailValue>>({ kind: "loading" });
  const [pendingAction, setPendingAction] = useState<ListingReviewAction | null>(null);
  const [reason, setReason] = useState("");
  const [isSubmitting, setIsSubmitting] = useState(false);
  const [actionError, setActionError] = useState<string | null>(null);
  const confirmationId = useId();
  const reasonId = useId();

  useEffect(() => {
    let isCurrent = true;
    setDetail({ kind: "loading" });
    Promise.all([
      getAgencyListing(tokenRef.current, agencyId, listingId),
      listListingTransitions(tokenRef.current, agencyId, listingId),
    ]).then(
      ([listing, history]) => {
        if (isCurrent) setDetail({ kind: "ready", value: { listing, history } });
      },
      (error: unknown) => {
        if (isCurrent) {
          setDetail({
            kind: "error",
            message: errorMessage(error, "No se pudo cargar el inmueble."),
          });
        }
      },
    );
    return () => {
      isCurrent = false;
    };
  }, [agencyId, listingId, detailReload, tokenRef]);

  function startAction(action: ListingReviewAction) {
    setActionError(null);
    setReason("");
    setPendingAction(action);
  }

  async function confirmAction() {
    if (!pendingAction || isSubmitting) return;
    const observation = pendingAction === "reject" ? reason.trim() : undefined;
    if (pendingAction === "reject" && !observation) return;

    setIsSubmitting(true);
    setActionError(null);
    try {
      await transitionListing(
        tokenRef.current,
        agencyId,
        listingId,
        pendingAction,
        observation,
      );
      onCompleted(ACTIONS[pendingAction].notice);
    } catch (error) {
      setPendingAction(null);
      if (error instanceof StaffListingsApiError && error.status === 409) {
        setActionError(CONFLICT);
        setDetailReload((value) => value + 1);
      } else {
        setActionError(
          errorMessage(error, "No se pudo completar la acción. Inténtalo nuevamente."),
        );
      }
    } finally {
      setIsSubmitting(false);
    }
  }

  return (
    <article className="review-detail">
      <button className="review-button review-button--link" onClick={onBack} type="button">
        Volver a la bandeja
      </button>

      {actionError ? (
        <p className="review-queue__message review-queue__message--error" role="alert">
          {actionError}
        </p>
      ) : null}

      {detail.kind === "loading" ? (
        <p aria-busy="true" className="review-queue__message">
          Cargando inmueble…
        </p>
      ) : null}
      {detail.kind === "error" ? (
        <div className="review-queue__message review-queue__message--error" role="alert">
          <p>{detail.message}</p>
          <button
            className="review-button review-button--secondary"
            onClick={() => setDetailReload((value) => value + 1)}
            type="button"
          >
            Reintentar
          </button>
        </div>
      ) : null}

      {detail.kind === "ready" ? (
        <>
          <header className="review-detail__header">
            <span className="review-list__badge">
              {STATUS_LABELS[detail.value.listing.approval_status]}
              {detail.value.listing.approval_status === "approved"
                ? detail.value.listing.is_published
                  ? " · Publicado en el catálogo"
                  : " · Sin publicar"
                : ""}
            </span>
            <h3>
              {detail.value.listing.city} · {detail.value.listing.zone}
            </h3>
            <p className="review-list__price">{priceLabel(detail.value.listing)}</p>
          </header>

          <dl className="review-detail__fields">
            <div>
              <dt>Operación</dt>
              <dd>{operationLabel(detail.value.listing)}</dd>
            </div>
            <div>
              <dt>Ambientes</dt>
              <dd>{roomsLabel(detail.value.listing)}</dd>
            </div>
            <div>
              <dt>Dirección exacta</dt>
              <dd>{detail.value.listing.exact_address ?? "Sin dirección registrada"}</dd>
            </div>
            <div>
              <dt>Descripción</dt>
              <dd>{detail.value.listing.description ?? "Sin descripción"}</dd>
            </div>
          </dl>

          <section aria-labelledby={`${confirmationId}-history`} className="review-history">
            <h4 id={`${confirmationId}-history`}>Historial</h4>
            <ol aria-label="Historial" className="review-history__list">
              {detail.value.history.map((entry) => (
                <li key={entry.id}>
                  <span className="review-history__action">{HISTORY_LABELS[entry.action]}</span>
                  <span className="review-history__meta">
                    {ROLE_LABELS[entry.actor_role] ?? entry.actor_role} ·{" "}
                    {formatDate(entry.created_at)}
                  </span>
                  {entry.observation ? (
                    <span className="review-history__observation">{entry.observation}</span>
                  ) : null}
                </li>
              ))}
            </ol>
          </section>

          {pendingAction ? (
            <div
              aria-labelledby={confirmationId}
              className="review-confirmation"
              role="group"
            >
              <h4 id={confirmationId}>{ACTIONS[pendingAction].confirmTitle}</h4>
              <p>{ACTIONS[pendingAction].consequence}</p>
              {pendingAction === "reject" ? (
                <div className="review-confirmation__field">
                  <label htmlFor={reasonId}>Motivo del rechazo</label>
                  <textarea
                    id={reasonId}
                    onChange={(event) => setReason(event.target.value)}
                    rows={3}
                    value={reason}
                  />
                </div>
              ) : null}
              <div className="review-actions">
                <button
                  className="review-button"
                  disabled={
                    isSubmitting || (pendingAction === "reject" && !reason.trim())
                  }
                  onClick={() => void confirmAction()}
                  type="button"
                >
                  {isSubmitting ? "Enviando…" : "Confirmar"}
                </button>
                <button
                  className="review-button review-button--secondary"
                  disabled={isSubmitting}
                  onClick={() => setPendingAction(null)}
                  type="button"
                >
                  Cancelar
                </button>
              </div>
            </div>
          ) : (
            <div className="review-actions">
              {availableActions(detail.value.listing).map((action) => (
                <button
                  className={
                    action === "reject" || action === "unpublish"
                      ? "review-button review-button--secondary"
                      : "review-button"
                  }
                  key={action}
                  onClick={() => startAction(action)}
                  type="button"
                >
                  {ACTIONS[action].label}
                </button>
              ))}
            </div>
          )}
        </>
      ) : null}
    </article>
  );
}
