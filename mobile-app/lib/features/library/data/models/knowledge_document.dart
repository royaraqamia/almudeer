import 'knowledge_constants.dart';

/// Issue #19: KnowledgeDocument now uses KnowledgeSource enum instead of magic strings
class KnowledgeDocument {
  final String text;
  final KnowledgeSource source;
  final DateTime? createdAt;
  final String? id;
  final String? filePath;

  const KnowledgeDocument({
    required this.text,
    this.source = KnowledgeSource.manual,
    this.createdAt,
    this.id,
    this.filePath,
  });

  factory KnowledgeDocument.fromJson(Map<String, dynamic> json) {
    String sourceStr = 'manual';
    if (json['metadata'] != null && json['metadata']['source'] != null) {
      sourceStr = json['metadata']['source'] as String;
    }

    return KnowledgeDocument(
      text: json['text'] as String? ?? '',
      source: KnowledgeSource.fromString(sourceStr),
      createdAt: json['metadata'] != null && 
                 json['metadata']['created_at'] != null
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
        'source': source.value,
        if (createdAt != null) 'created_at': createdAt!.toIso8601String(),
      },
      if (id != null) 'id': id,
      if (filePath != null) 'file_path': filePath,
    };
  }
  
  /// Check if this is a file document
  bool get isFile => source == KnowledgeSource.file;
  
  /// Check if this is a text document
  bool get isText => source != KnowledgeSource.file;
}
