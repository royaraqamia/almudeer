"""
FIX CODE-002: Centralized constants for tasks feature
This prevents magic numbers and strings throughout the codebase
"""

# Task constraints
MAX_TITLE_LENGTH = 500
MAX_DESCRIPTION_LENGTH = 5000
MAX_CATEGORY_LENGTH = 100
MAX_SUBTASKS = 100
MAX_ATTACHMENTS = 20

# File upload constraints
# FIX: Standardized with library.py to 20MB for consistency
MAX_FILE_SIZE = 20 * 1024 * 1024  # 20MB (matches library MAX_FILE_SIZE)
ALLOWED_IMAGE_TYPES = ['image/jpeg', 'image/png', 'image/gif']
ALLOWED_FILE_EXTENSIONS = ['jpg', 'jpeg', 'png', 'gif', 'pdf', 'doc', 'docx']

# Sync configuration
SYNC_TIMEOUT_SECONDS = 30
FETCH_TASKS_TIMEOUT_SECONDS = 60
SYNC_BATCH_SIZE = 5
MAX_PENDING_SYNC_ITEMS = 1000

# Pagination
DEFAULT_PAGE_SIZE = 50
MAX_PAGE_SIZE = 200

# Cache configuration
ANALYTICS_CACHE_TTL_SECONDS = 300  # 5 minutes
ANALYTICS_CACHE_MAX_ENTRIES = 100

# Debounce timings (milliseconds)
SEARCH_DEBOUNCE_MS = 300
SAVE_DEBOUNCE_MS = 1500
TYPING_INDICATOR_DEBOUNCE_MS = 500

# Alarm configuration
MAX_ALARMS_PER_TASK = 10
ALARM_SNOOZE_MINUTES = 5
MAX_SNOOZE_COUNT = 3

# Recurrence patterns
RECURRENCE_DAILY = 'daily'
RECURRENCE_WEEKLY = 'weekly'
RECURRENCE_MONTHLY = 'monthly'

# Priority levels
PRIORITY_LOW = 'low'
PRIORITY_MEDIUM = 'medium'
PRIORITY_HIGH = 'high'
PRIORITY_URGENT = 'urgent'

# Visibility
VISIBILITY_SHARED = 'shared'
VISIBILITY_PRIVATE = 'private'

# Task roles
ROLE_OWNER = 'owner'
ROLE_ASSIGNEE = 'assignee'
ROLE_VIEWER = 'viewer'

# Rate limiting
RATE_LIMIT_PER_MINUTE = 60
RATE_LIMIT_BURST = 10

# LWW conflict resolution
LWW_CLOCK_SKEW_TOLERANCE_SECONDS = 5

# Error messages
ERROR_TASK_NOT_FOUND = "Task not found"
ERROR_PERMISSION_DENIED = "Permission denied"
ERROR_SYNC_FAILED = "Sync failed"
ERROR_INVALID_DATA = "Invalid task data"
