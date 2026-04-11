class HistoryFile {
  final String name;
  final int size;

  HistoryFile({required this.name, required this.size});

  factory HistoryFile.fromJson(Map<String, dynamic> json) => HistoryFile(
        name: json['name'],
        size: json['size'],
      );

  Map<String, dynamic> toJson() => {
        'name': name,
        'size': size,
      };
}

class HistoryEntry {
  final String id;
  final String partnerName;
  final List<HistoryFile> files;
  final int totalSize;
  final String direction; // 'incoming' or 'outgoing'
  final DateTime timestamp;
  final String status; // 'completed' or 'error'
  final String? errorMessage;
  final int durationMillis;

  HistoryEntry({
    required this.id,
    required this.partnerName,
    required this.files,
    required this.totalSize,
    required this.direction,
    required this.timestamp,
    required this.status,
    this.errorMessage,
    required this.durationMillis,
  });

  factory HistoryEntry.fromJson(Map<String, dynamic> json) => HistoryEntry(
        id: json['id'],
        partnerName: json['partnerName'],
        files: (json['files'] as List).map((e) => HistoryFile.fromJson(e)).toList(),
        totalSize: json['totalSize'],
        direction: json['direction'],
        timestamp: DateTime.parse(json['timestamp']),
        status: json['status'],
        errorMessage: json['errorMessage'],
        durationMillis: json['durationMillis'],
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'partnerName': partnerName,
        'files': files.map((e) => e.toJson()).toList(),
        'totalSize': totalSize,
        'direction': direction,
        'timestamp': timestamp.toIso8601String(),
        'status': status,
        'errorMessage': errorMessage,
        'durationMillis': durationMillis,
      };
}
