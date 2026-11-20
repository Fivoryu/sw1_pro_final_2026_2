import 'package:flutter/widgets.dart';

import 'customer_tab.dart';

export 'customer_tab.dart';

/// The shell and its pushed pages share the same three destinations. This
/// scope exposes tab selection, never a booking, quote or payment controller.
class CustomerTabs extends InheritedWidget {
  const CustomerTabs({
    super.key,
    required this.selected,
    required this.select,
    required this.canVisitReservations,
    required super.child,
  });

  final CustomerTab selected;
  final ValueChanged<CustomerTab> select;
  final bool Function() canVisitReservations;

  static CustomerTabs? maybeOf(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<CustomerTabs>();

  @override
  bool updateShouldNotify(CustomerTabs oldWidget) =>
      selected != oldWidget.selected ||
      canVisitReservations != oldWidget.canVisitReservations;
}

class CustomerTabHost extends StatefulWidget {
  const CustomerTabHost({
    super.key,
    required this.canVisitReservations,
    required this.child,
  });
  final bool Function() canVisitReservations;
  final Widget child;

  @override
  State<CustomerTabHost> createState() => _CustomerTabHostState();
}

class _CustomerTabHostState extends State<CustomerTabHost> {
  CustomerTab _selected = CustomerTab.explore;

  @override
  Widget build(BuildContext context) => CustomerTabs(
    selected: _selected,
    select: (tab) => setState(() => _selected = tab),
    canVisitReservations: widget.canVisitReservations,
    child: widget.child,
  );
}
