class KnowledgeDocument {
  final String text;
  final String source;
  final DateTime? createdAt;
  final String? id;
  final String? filePath;

  const KnowledgeDocument({
    required this.text,
    this.source = 'manual',
    this.createdAt,
    this.id,
    this.filePath,
  });

  factory KnowledgeDocument.fromJson(Map<String, dynamic> json) {
    return KnowledgeDocument(
      text: json['text'] as String? ?? '',
      source: json['metadata'] != null
          ? (json['metadata']['source'] as String? ?? 'manual')
          : 'manual',
      createdAt:
          json['metadata'] != null && json['metadata']['created_at'] != null
          ? DateTime.tryParse(json['metadata']['created_at'])
          : null,
      id: json['id'] as String?,
      filePath: json['file_path'] as String?,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'text': text,
      'metadata': {
        'source': source,
        if (createdAt != null) 'created_at': createdAt!.toIso8601String(),
      },
      if (id != null) 'id': id,
      if (filePath != null) 'file_path': filePath,
    };
  }
}
