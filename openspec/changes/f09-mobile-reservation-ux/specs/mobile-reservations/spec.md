## ADDED Requirements

### Requirement: Seguimiento móvil de una solicitud de reserva
La app DEBE mostrar los totales recibidos en la moneda elegida cuando el servidor informa una conversión. La selección del medio DEBE explicar su uso y respetar las monedas admitidas por el contrato existente. Una solicitud creada DEBE quedar accesible desde el detalle aunque la apertura del medio de pago falle.

#### Scenario: Stripe termina antes de que el servidor confirme el depósito
- **WHEN** la interfaz de Stripe devuelve éxito y la API todavía no confirma el depósito
- **THEN** Mis reservas muestra la verificación en curso y no ofrece repetir el pago durante ese estado observado en la sesión.
