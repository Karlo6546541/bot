/// Jedna točka povijesti vrijednosti korisnika (za grafikon portfolija).
/// Bilježi se nakon svake promjene kredita ili portfolija.
class PortfolioPoint {
  const PortfolioPoint({
    required this.time,
    required this.credits,
    required this.portfolio,
  });

  final DateTime time;
  final double credits;
  final double portfolio;

  double get total => credits + portfolio;

  Map<String, dynamic> toMap() => {
    't': time.toIso8601String(),
    'c': credits,
    'p': portfolio,
  };

  factory PortfolioPoint.fromMap(Map<dynamic, dynamic> map) => PortfolioPoint(
    time: DateTime.parse(map['t'] as String),
    credits: (map['c'] as num).toDouble(),
    portfolio: (map['p'] as num).toDouble(),
  );
}
