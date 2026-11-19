## MODIFIED Requirements

### Requirement: Configuración de Stripe Connect en modo de prueba (F09.8)
El administrador de la agencia DEBE indicar el correo de contacto al iniciar el alta. El backend DEBE validarlo y usar Accounts v2 con configuración `recipient` y transferencias solicitadas.

#### Scenario: Alta de una agencia sin cuenta
- **WHEN** el administrador autorizado indica un correo válido
- **THEN** se crea una cuenta de prueba y se devuelve un enlace de onboarding de Stripe.

#### Scenario: Reapertura del onboarding
- **WHEN** la agencia ya tiene una cuenta vinculada
- **THEN** se usa esa cuenta y no se pide otro correo ni se crea una segunda cuenta.
