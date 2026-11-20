import '../../customer_tab.dart';
import 'guide_assistant.dart';
import 'guide_content.dart';

enum DetailReservationStep {
  unavailable,
  signIn,
  quote,
  chooseMethod,
  alreadyRequested,
  busy,
}

/// Lives as long as one open chat. Unrelated questions return to the normal
/// guide; neither history nor the current topic is shared between sheets.
class ReservationConversation {
  static const _start = 'Iniciar una reserva';
  static const _follow = 'Consultar mis reservas';
  static const _pay = '¿Y cómo pago?';
  static const _assistant = GuideAssistant();
  ReservationIntent? _topic;

  GuideReply answer(
    String question,
    GuideScreen screen, {
    DetailReservationStep step = DetailReservationStep.quote,
  }) {
    final words = GuideAssistant.normalize(question);
    if (words == 'reserva' || words == 'reservas') {
      _topic = null;
      return const GuideReply(
        '¿Querés iniciar una o consultar una que ya hiciste?',
        [_start, _follow],
      );
    }
    if (_topic != null &&
        const {
          'y como pago',
          'como pago',
          'y el pago',
          'como pagar',
        }.contains(words)) {
      if (_topic == ReservationIntent.follow) {
        return GuideReply(
          'En la pestaña «Reservas», revisá el estado de tu depósito. '
          'Si está pendiente, la tarjeta de la reserva muestra las opciones disponibles. '
          'La guía no confirma pagos.',
          const [_follow, _start],
          destination: screen == GuideScreen.reservations
              ? null
              : CustomerTab.reservations,
        );
      }
      return const GuideReply(
        'Es el depósito de la reserva, no el precio total. '
        'En «Elegí cómo reservar», «Tarjeta de prueba» admite BOB o USD; '
        '«Wallet de prueba» requiere una wallet vinculada. Elegir un medio puede crear la reserva. '
        'Para practicar, salí de esa hoja sin elegir un medio.',
        [_start, _follow],
      );
    }
    _topic =
        words == GuideAssistant.normalize(_start) ||
            words == GuideAssistant.normalize(GuideContent.startReservation)
        ? ReservationIntent.start
        : words == GuideAssistant.normalize(GuideContent.trackReservation)
        ? ReservationIntent.follow
        : GuideAssistant.reservationIntent(question);
    switch (_topic) {
      case ReservationIntent.start:
        if (screen == GuideScreen.listingDetail) {
          return switch (step) {
            DetailReservationStep.unavailable => const GuideReply(
              'Ahora no se puede cotizar este inmueble. Volvé a intentarlo cuando el detalle y el servicio estén disponibles.',
              [_follow, _start],
            ),
            DetailReservationStep.signIn => const GuideReply(
              'Para solicitar una reserva, primero iniciá sesión en «Cuenta». Después volvé al inmueble desde «Explorar».',
              [_pay, _follow],
              destination: CustomerTab.account,
            ),
            DetailReservationStep.quote => const GuideReply(
              'En este detalle, revisá los opcionales y tocá «Calcular cotización». Con el resumen vigente podrás elegir cómo reservar.',
              [_pay, _follow],
            ),
            DetailReservationStep.chooseMethod => const GuideReply(
              'Ya tenés una cotización vigente. Tocá «Elegir cómo reservar». Para practicar, detenete en «Elegí cómo reservar» sin elegir tarjeta ni wallet.',
              [_pay, _follow],
            ),
            DetailReservationStep.alreadyRequested => const GuideReply(
              'Ya hay una solicitud para este inmueble. Tocá «Ver mi reserva» para consultar su estado.',
              [_follow, _pay],
            ),
            DetailReservationStep.busy => const GuideReply(
              'Esperá a que termine la operación en curso antes de continuar.',
              [_pay, _follow],
            ),
          };
        }
        return GuideReply(
          screen == GuideScreen.catalog
              ? 'Ya estás en «Explorar». Abrí la tarjeta del inmueble que querés reservar.'
              : 'Volvé a las pestañas y abrí «Explorar». Después, abrí la tarjeta del inmueble que querés reservar.',
          const [_pay, _follow],
          destination: screen == GuideScreen.catalog
              ? null
              : CustomerTab.explore,
        );
      case ReservationIntent.follow:
        return GuideReply(
          screen == GuideScreen.reservations
              ? 'Ya estás en la pestaña «Reservas». Con tu sesión iniciada, buscá la tarjeta de tu reserva para ver su estado.'
              : 'Con tu sesión iniciada, abrí la pestaña «Reservas» y buscá la tarjeta de tu reserva para ver su estado.',
          const [_pay, _start],
          destination: screen == GuideScreen.reservations
              ? null
              : CustomerTab.reservations,
        );
      case null:
        return _assistant.answer(question, screen);
    }
  }
}
