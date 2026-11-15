/// Short local time for chat lists and bubbles: `HH:mm`, with the date when
/// the instant is not today.
String formatChatTime(DateTime instant, {DateTime? now}) {
  final local = instant.toLocal();
  final reference = (now ?? DateTime.now()).toLocal();
  String two(int value) => value.toString().padLeft(2, '0');
  final time = '${two(local.hour)}:${two(local.minute)}';
  final today =
      local.year == reference.year &&
      local.month == reference.month &&
      local.day == reference.day;
  return today ? time : '${two(local.day)}/${two(local.month)} $time';
}
