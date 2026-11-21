import '../l10n/tr.dart';

/// Razlog prijave oglasa ili korisnika.
enum ReportReason {
  scam('Prevara ili lažni oglas'),
  prohibited('Zabranjen predmet'),
  wrongInfo('Netočan opis ili slike'),
  offensive('Uvredljiv sadržaj ili ponašanje'),
  spam('Spam'),
  other('Nešto drugo');

  const ReportReason(this._label);
  final String _label;
  String get label => t(_label);

  static ReportReason fromName(String? n) => ReportReason.values.firstWhere(
    (r) => r.name == n,
    orElse: () => ReportReason.other,
  );
}

enum ReportStatus { open, resolved, dismissed }

/// Prijava oglasa (predmeta) ili korisnika — pregledava je admin.
class Report {
  const Report({
    required this.id,
    required this.reporterId,
    required this.reporterLabel,
    required this.targetType,
    required this.targetId,
    required this.targetLabel,
    required this.reason,
    required this.createdAt,
    this.note = '',
    this.status = ReportStatus.open,
    this.resolvedAt,
  });

  final String id;
  final String reporterId;
  final String reporterLabel;

  /// 'device' | 'user' | 'appeal' (žalba na odluku; [targetId] je prijava).
  final String targetType;
  final String targetId;

  /// Naziv predmeta ili @korisnik u trenutku prijave.
  final String targetLabel;
  final ReportReason reason;
  final String note;
  final ReportStatus status;
  final DateTime createdAt;
  final DateTime? resolvedAt;

  static const maxNote = 300;

  bool get isOpen => status == ReportStatus.open;
  bool get isDevice => targetType == 'device';
  bool get isAppeal => targetType == 'appeal';

  Report close(ReportStatus s, DateTime at) => Report(
    id: id,
    reporterId: reporterId,
    reporterLabel: reporterLabel,
    targetType: targetType,
    targetId: targetId,
    targetLabel: targetLabel,
    reason: reason,
    note: note,
    status: s,
    createdAt: createdAt,
    resolvedAt: at,
  );

  Map<String, dynamic> toMap() => {
    'id': id,
    'reporterId': reporterId,
    'reporterLabel': reporterLabel,
    'targetType': targetType,
    'targetId': targetId,
    'targetLabel': targetLabel,
    'reason': reason.name,
    'note': note,
    'status': status.name,
    'createdAt': createdAt.toIso8601String(),
    'resolvedAt': resolvedAt?.toIso8601String(),
  };

  factory Report.fromMap(Map<dynamic, dynamic> m) => Report(
    id: m['id'] as String,
    reporterId: m['reporterId'] as String,
    reporterLabel: m['reporterLabel'] as String? ?? '',
    targetType: m['targetType'] as String,
    targetId: m['targetId'] as String,
    targetLabel: m['targetLabel'] as String? ?? '',
    reason: ReportReason.fromName(m['reason'] as String?),
    note: m['note'] as String? ?? '',
    status: ReportStatus.values.firstWhere(
      (s) => s.name == m['status'],
      orElse: () => ReportStatus.open,
    ),
    createdAt: DateTime.parse(m['createdAt'] as String),
    resolvedAt: m['resolvedAt'] == null
        ? null
        : DateTime.parse(m['resolvedAt'] as String),
  );
}
