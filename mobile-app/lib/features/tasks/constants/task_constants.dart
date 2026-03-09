// FIX CODE-002: Centralized constants for tasks feature
// This prevents magic numbers and strings throughout the codebase

class TaskConstants {
  // Task constraints
  static const int maxTitleLength = 500;
  static const int maxDescriptionLength = 5000;
  static const int maxCategoryLength = 100;
  static const int maxSubTasks = 100;
  static const int maxAttachments = 20;
  
  // File upload constraints
  static const int maxFileSize = 10 * 1024 * 1024; // 10MB
  static const List<String> allowedImageTypes = ['image/jpeg', 'image/png', 'image/gif'];
  static const List<String> allowedFileExtensions = ['jpg', 'jpeg', 'png', 'gif', 'pdf', 'doc', 'docx'];
  
  // Sync configuration
  static const int syncTimeoutSeconds = 30;
  static const int fetchTasksTimeoutSeconds = 60;
  static const int syncBatchSize = 5;
  static const int maxPendingSyncItems = 1000;
  
  // Pagination
  static const int defaultPageSize = 50;
  static const int maxPageSize = 200;
  
  // Cache configuration
  static const int analyticsCacheTTLSeconds = 300; // 5 minutes
  static const int alarmRescheduleIntervalHours = 24;
  static const int commentCacheStaleSeconds = 30;
  
  // Debounce timings (milliseconds)
  static const int searchDebounceMs = 300;
  static const int saveDebounceMs = 1500;
  static const int typingIndicatorDebounceMs = 500;
  
  // Alarm configuration
  static const int maxAlarmsPerTask = 10;
  static const int alarmSnoozeMinutes = 5;
  static const int maxSnoozeCount = 3;
  
  // Recurrence patterns
  static const String recurrenceDaily = 'daily';
  static const String recurrenceWeekly = 'weekly';
  static const String recurrenceMonthly = 'monthly';
  
  // Priority levels
  static const String priorityLow = 'low';
  static const String priorityMedium = 'medium';
  static const String priorityHigh = 'high';
  static const String priorityUrgent = 'urgent';
  
  // Visibility
  static const String visibilityShared = 'shared';
  static const String visibilityPrivate = 'private';
  
  // Task roles
  static const String roleOwner = 'owner';
  static const String roleAssignee = 'assignee';
  static const String roleViewer = 'viewer';
  
  // Rate limiting
  static const int rateLimitPerMinute = 60;
  static const int rateLimitBurst = 10;
  
  // Error messages
  static const String errorTaskNotFound = 'Task not found';
  static const String errorPermissionDenied = 'Permission denied';
  static const String errorSyncFailed = 'Sync failed';
  static const String errorInvalidData = 'Invalid task data';
}
