function RoomForgeMark() {
  return (
    <svg
      aria-hidden="true"
      className="brand-mark"
      fill="none"
      viewBox="0 0 42 42"
    >
      <path
        d="M6 35V7h12.5c8.8 0 14.5 5.4 14.5 13.9 0 8.7-5.7 14.1-14.5 14.1H6Z"
        stroke="currentColor"
        strokeWidth="1.4"
      />
      <path d="M6 20.8h26.8M19.4 7v28" stroke="currentColor" strokeWidth="1.2" />
      <circle cx="32.5" cy="34.5" r="3.5" fill="currentColor" />
    </svg>
  );
}

export function AuthEditorialPanel() {
  return (
    <section className="editorial-panel" aria-label="RoomForge">
      <div className="brand-lockup" aria-label="RoomForge">
        <RoomForgeMark />
        <span className="brand-wordmark">ROOMFORGE</span>
      </div>

      <svg
        aria-hidden="true"
        className="architecture-art"
        fill="none"
        preserveAspectRatio="xMidYMax meet"
        viewBox="0 0 620 540"
      >
        <path d="M88 540V214L307 72l225 142v326" stroke="currentColor" />
        <path d="M145 540V251l162-111 168 111v289" stroke="currentColor" />
        <path d="M206 540V286l101-70 106 70v254" stroke="currentColor" />
        <path d="M32 540h548M88 453h444M145 366h330M206 286h212" stroke="currentColor" />
        <path d="M307 72v468M88 214l444 326M532 214 88 540" stroke="currentColor" />
        <circle cx="307" cy="72" r="5" fill="currentColor" />
      </svg>

      <div className="editorial-copy">
        <p className="eyebrow editorial-eyebrow">
          <span className="eyebrow-dot" />
          ESPACIOS CONECTADOS · ROOMFORGE
        </p>
        <p className="editorial-title">
          Un espacio de trabajo pensado para cada lugar.
        </p>
        <p className="editorial-description">
          Acceso privado para el equipo que da forma a las experiencias de RoomForge.
        </p>
      </div>

      <footer className="editorial-footer">
        <span>PLATAFORMA DE PERSONAL</span>
        <span>LA PAZ · BOLIVIA</span>
      </footer>
    </section>
  );
}
