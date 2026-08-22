# Enfoque blockchain del escrow — RoomForge

| Campo | Valor |
| --- | --- |
| Artefacto | Plan "por dónde empezar" para contratos inteligentes |
| Estado | Propuesto — aprobación del equipo pendiente |
| Alcance | Escrow de reserva con token de prueba (BR-052..BR-058, RF-027) |
| Superficie | Blockchain (Solidity/Hardhat) + Backend; PBs PB-040, PB-041, PB-042, PB-043 |

## 1. Desmitificar: qué necesitamos en realidad

El blockchain de RoomForge es **muy chico**:

- **Uno (1) contrato de escrow**: maneja estados `pendiente → escrowed (bloqueado) → released (liberado)` o `refunded (reembolsado)`.
- **Un (1) token ERC20 de prueba**: sin valor real, existe solo para mover "depósitos" simulados.
- **Una red local de pruebas** (Hardhat): nada de minería, nodos, gas real ni redes públicas.

No hay que saber blockchain para empezar: hay que saber **estados y transiciones**, y eso ya está definido en las reglas (BR-052..058). El contrato es una máquina de estados con auditoría.

## 2. Herramientas (ya decididas) y para qué sirven

| Herramienta | Rol |
| --- | --- |
| Solidity | Lenguaje del contrato |
| Hardhat | Red local + compilación + tests automatizados (JS/TS) |
| OpenZeppelin | Contratos reutilizables (ERC20 de prueba, Ownable, ReentrancyGuard) |
| Remix (IDE web) | Solo para aprender/apuntar, sin instalación |

## 3. Camino de aprendizaje (no requiere experiencia previa)

1. **Semana previa al desarrollo del escrow**: 1 sesión Remix con un contrato de ejemplo (contador con estados) para familiarizarse con la sintaxis.
2. **Tutorial oficial Hardhat** ("Getting started" ~1-2 h): deploy de un contrato simple + test en consola.
3. **Recién después**: dividir PB-041 en TASKs (sección 5) y ejecutar con ayuda de IA como apoyo (equipo generalista).
4. **Regla**: no se escribe el escrow real antes de que dos integrantes hayan desplegado el contrato de ejemplo en local.

## 4. Cómo se integra con el backend (FastAPI)

- La **API sigue siendo la autoridad** de estados de reserva (PostgreSQL persiste todo).
- El contrato **registra y valida** el movimiento del token de prueba: bloqueo, liberación, reembolso.
- El backend **escucha eventos del contrato** (listener) y actualiza PostgreSQL con idempotencia; si el evento falta, el estado lo reconcilia el job de expiración (BR-057).
- El token se acuña en el deploy local; las reservas usan ese token, nunca ether real.

## 5. TBD del escrow (GAP-074) — división en TASKs de PB-041

| TASK | Descripción | Depende de |
| --- | --- | --- |
| T1 | Setup Hardhat + red local + contrato ERC20Test (OpenZeppelin) | aprendizaje (sección 3) |
| T2 | Contrato `EscrowRoomforge`: estados, dueño (tenant), `inmuebleId`, `reservaId` | T1 |
| T3 | Funciones `deposit` (bloquear), `release` (liberar), `refund` (reembolsar), `expire` con `onlyOwner` y guardas de estado | T2 |
| T4 | Eventos (`Deposited`, `Released`, `Refunded`, `Expired`) + pruebas unitarias de transiciones y transiciones inválidas | T3 |
| T5 | Listener backend (FastAPI) que escucha eventos y actualiza PostgreSQL idempotentemente | T4 |
| T6 | Integración API (`POST /reservas/{id}/escrow`) + pruebas de contrato (caja negra) | T5 |
| T7 | Script de demo: acuñar, reservar, aceptar, reembolsar — reproducible para la presentación | T6 |

## 6. Fallback (importante para el plan)

Si el contrato no estuviera listo al cerrar el sprint 2, el backend **simula el escrow** con el mismo flujo de estados (mismo precedente que el simulador de facturación). El blockchain es una **demostración** del MVP, no el soporte transaccional; la demo siempre funciona.

## 7. Riesgo y mitigación

| Riesgo | Mitigación |
| --- | --- |
| Nadie sabe Solidity | Plan de aprendizaje previo (sección 3); IA como apoyo; alcance mínimo |
| Contrato con bugs (reentrancia, transiciones duplicadas) | OpenZeppelin (ReentrancyGuard), tests T4, transiciones únicas ya exigidas por BR-056 |
| Integración evento → backend frágil | Listener idempotente + reconciliación con job de expiración |
| No llega a tiempo | Fallback simulado (sección 6); sin dinero real, riesgo acotado |
