class CitizenServiceNotice {
  const CitizenServiceNotice({
    required this.uniqueId,
    required this.reasonLabel,
    required this.reasonText,
  });

  final String uniqueId;
  final String reasonLabel;
  final String reasonText;
  String get explanation =>
      reasonText.trim().isNotEmpty ? reasonText.trim() : reasonLabel;

  static CitizenServiceNotice? fromResponse(Map<String, dynamic> json) {
    final value = json['service_notice'];
    if (value is! Map) return null;
    return CitizenServiceNotice(
      uniqueId: value['unique_id']?.toString() ?? '',
      reasonLabel: value['reason_label']?.toString() ?? 'Operational issue',
      reasonText: value['reason_text']?.toString() ?? '',
    );
  }
}

/// The logged-in citizen's household stop on today's trip
/// (`GET citizen/my-pickup-today/`).
class CitizenPickupToday {
  const CitizenPickupToday({
    required this.uniqueId,
    required this.status,
    this.statusReason,
    this.statusUpdatedAt,
    this.collectedAt,
    this.collectedWeightKg,
    this.collectionImageUrl,
    this.statusEvidenceImageUrl,
    this.wasteBreakdown = const [],
    this.customerAvailableAt,
    this.customerAvailableNote,
    this.missedPickupTicketNo,
  });

  final String uniqueId;

  /// Backend status: Pending, Collected, Collect Later, Not Available, ...
  final String status;
  final String? statusReason;
  final DateTime? statusUpdatedAt;
  final DateTime? collectedAt;
  final double? collectedWeightKg;
  final String? collectionImageUrl;
  final String? statusEvidenceImageUrl;
  final List<CitizenPickupWaste> wasteBreakdown;

  String? get proofImageUrl => collectionImageUrl ?? statusEvidenceImageUrl;

  String get wasteDescription {
    final names = wasteBreakdown.map((item) => item.wasteType).toList();
    return names.isEmpty ? 'Waste' : names.join(', ');
  }

  /// When the citizen tapped "I'm home now" (null until they do).
  final DateTime? customerAvailableAt;
  final String? customerAvailableNote;

  /// Ticket raised automatically when a flagged pickup still ended Not
  /// Available.
  final String? missedPickupTicketNo;

  String get _s => status.toLowerCase();
  bool get isCollected => _s == 'collected';
  bool get isCollectLater => _s == 'collect later' || _s == 'skipped';
  bool get isNotAvailable =>
      _s == 'not available' || _s == 'missed' || _s == 'not collected';
  bool get canSayImHome => isCollectLater && customerAvailableAt == null;

  static DateTime? _date(dynamic v) =>
      v == null ? null : DateTime.tryParse(v.toString())?.toLocal();

  /// Returns null when there is no stop for the citizen today.
  static CitizenPickupToday? fromResponse(Map<String, dynamic> json) {
    final stop = json['stop'];
    if (stop is! Map) return null;
    final m = Map<String, dynamic>.from(stop);
    return CitizenPickupToday(
      uniqueId: m['unique_id']?.toString() ?? '',
      status: m['status']?.toString() ?? 'Pending',
      statusReason: m['status_reason']?.toString(),
      statusUpdatedAt: _date(m['status_updated_at']),
      collectedAt: _date(m['collected_at']),
      collectedWeightKg: double.tryParse('${m['collected_weight_kg'] ?? ''}'),
      collectionImageUrl: _nonEmpty(m['collection_image_url']),
      statusEvidenceImageUrl: _nonEmpty(m['status_evidence_image_url']),
      wasteBreakdown: (m['waste_breakdown'] as List? ?? const [])
          .whereType<Map>()
          .map((item) =>
              CitizenPickupWaste.fromJson(Map<String, dynamic>.from(item)))
          .toList(growable: false),
      customerAvailableAt: _date(m['customer_available_at']),
      customerAvailableNote: m['customer_available_note']?.toString(),
      missedPickupTicketNo: m['missed_pickup_ticket_no']?.toString(),
    );
  }

  static String? _nonEmpty(dynamic value) {
    final text = value?.toString().trim() ?? '';
    return text.isEmpty ? null : text;
  }
}

class CitizenPickupWaste {
  const CitizenPickupWaste({required this.wasteType, required this.weightKg});

  final String wasteType;
  final double weightKg;

  factory CitizenPickupWaste.fromJson(Map<String, dynamic> json) =>
      CitizenPickupWaste(
        wasteType: json['waste_type']?.toString() ?? 'Waste',
        weightKg: double.tryParse('${json['weight_kg'] ?? ''}') ?? 0,
      );
}
