/// Issue #19: Enum for knowledge document sources - replaces magic strings
enum KnowledgeSource {
  manual,
  mobileApp,
  file;

  String get value {
    switch (this) {
      case KnowledgeSource.manual:
        return 'manual';
      case KnowledgeSource.mobileApp:
        return 'mobile_app';
      case KnowledgeSource.file:
        return 'file';
    }
  }

  static KnowledgeSource fromString(String value) {
    switch (value) {
      case 'manual':
        return KnowledgeSource.manual;
      case 'mobile_app':
        return KnowledgeSource.mobileApp;
      case 'file':
        return KnowledgeSource.file;
      default:
        return KnowledgeSource.manual;
    }
  }
}

/// Issue #14: Constants for knowledge base validation
class KnowledgeBaseConstants {
  // File size limit: 20MB (should ideally be fetched from backend config)
  static const int maxFileSize = 20 * 1024 * 1024; // 20MB
  
  // Maximum text length for knowledge documents
  static const int maxTextLength = 15000;
  
  // Allowed file extensions for uploads
  static const List<String> allowedFileExtensions = [
    '.pdf', 
    '.txt', 
    '.md', 
    '.doc', 
    '.docx', 
    '.xls', 
    '.xlsx', 
    '.csv'
  ];
  
  // Cache key prefix for knowledge documents (Issue #7)
  static const String cacheKeyPrefix = 'knowledge_';
}
