import '../l10n/tr.dart';

enum SwapStatus {
  pending('Čeka odgovor'),
  accepted('Prihvaćeno'),
  declined('Odbijeno'),
  cancelled('Povučeno'),
  failed('Nije uspjelo');

  const SwapStatus(this._label);
  final String _label;
  String get label => t(_label);
}

/// Ponuda zamjene: "dam svoj predmet (+ krediti) za tvoj predmet".
/// Krediti ([extraCredits]) plaća onaj koji nudi; platforma uzima 5% fee
/// od svakog nadoplate.
class SwapOffer {
  const SwapOffer({
    required this.id,
    required this.fromId,
    required this.toId,
    required this.wantedDeviceId,
    required this.wantedName,
    required this.offeredDeviceId,
    required this.offeredName,
    required this.createdAt,
    this.extraCredits = 0,
    this.message = '',
    this.status = SwapStatus.pending,
    this.respondedAt,
  });

  final String id;

  /// Tko nudi zamjenu.
  final String fromId;

  /// Vlasnik željenog predmeta.
  final String toId;
  final String wantedDeviceId;
  final String wantedName;
  final String offeredDeviceId;
  final String offeredName;

  /// Nadoplata u kreditima (plaća [fromId]).
  final double extraCredits;
  final String message;
  final SwapStatus status;
  final DateTime createdAt;
  final DateTime? respondedAt;

  static const maxMessage = 200;

  bool get isPending => status == SwapStatus.pending;

  SwapOffer withStatus(SwapStatus s, DateTime at) => SwapOffer(
    id: id,
    fromId: fromId,
    toId: toId,
    wantedDeviceId: wantedDeviceId,
    wantedName: wantedName,
    offeredDeviceId: offeredDeviceId,
    offeredName: offeredName,
    createdAt: createdAt,
    extraCredits: extraCredits,
    message: message,
    status: s,
    respondedAt: at,
  );

  Map<String, dynamic> toMap() => {
    'id': id,
    'fromId': fromId,
    'toId': toId,
    'wantedDeviceId': wantedDeviceId,
    'wantedName': wantedName,
    'offeredDeviceId': offeredDeviceId,
    'offeredName': offeredName,
    'extraCredits': extraCredits,
    'message': message,
    'status': status.name,
    'createdAt': createdAt.toIso8601String(),
    'respondedAt': respondedAt?.toIso8601String(),
  };

  factory SwapOffer.fromMap(Map<dynamic, dynamic> m) => SwapOffer(
    id: m['id'] as String,
    fromId: m['fromId'] as String,
    toId: m['toId'] as String,
    wantedDeviceId: m['wantedDeviceId'] as String,
    wantedName: m['wantedName'] as String? ?? '',
    offeredDeviceId: m['offeredDeviceId'] as String,
    offeredName: m['offeredName'] as String? ?? '',
    extraCredits: (m['extraCredits'] as num?)?.toDouble() ?? 0,
    message: m['message'] as String? ?? '',
    status: SwapStatus.values.firstWhere(
      (s) => s.name == m['status'],
      orElse: () => SwapStatus.pending,
    ),
    createdAt: DateTime.parse(m['createdAt'] as String),
    respondedAt: m['respondedAt'] == null
        ? null
        : DateTime.parse(m['respondedAt'] as String),
  );
}
