class Departure {
  const Departure({required this.time, this.destination});

  final DateTime time;
  final String? destination;

  bool get isPast => time.isBefore(DateTime.now());
}
