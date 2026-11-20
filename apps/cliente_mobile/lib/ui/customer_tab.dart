enum CustomerTab {
  explore('Explorar'),
  reservations('Reservas'),
  account('Cuenta');

  const CustomerTab(this.label);
  final String label;
}
