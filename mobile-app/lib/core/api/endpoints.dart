/// API endpoints for Al-Mudeer backend
class Endpoints {
  // Prevent instantiation
  Endpoints._();

  /// Base URL - Production backend
  static const String baseUrl = 'https://almudeer.up.railway.app';

  // Authentication
  static const String validateLicense = '/api/admin/subscription/validate-key';
  static const String login = '/api/auth/login';
  static const String refresh = '/api/auth/refresh';
  static const String userInfo = '/api/auth/me';
  static const String logout = '/api/auth/logout';
  // activeSessions and revokeSession removed

  // Inbox & Conversations
  static const String inbox = '/api/integrations/inbox';
  static const String conversations = '/api/integrations/conversations';
  static const String conversationStats =
      '/api/integrations/conversations/stats';

  static String deleteConversation(String senderContact) =>
      '/api/integrations/conversations/${Uri.encodeComponent(senderContact)}';
  static String clearConversation(String senderContact) =>
      '/api/integrations/conversations/${Uri.encodeComponent(senderContact)}/clear';
  static String conversationDetail(String senderContact) =>
      '/api/integrations/conversations/${Uri.encodeComponent(senderContact)}';
  static String conversationAttachments(String senderContact) =>
      '/api/integrations/conversations/${Uri.encodeComponent(senderContact)}/attachments';
  static String sendMessage(String senderContact) =>
      '/api/integrations/conversations/${Uri.encodeComponent(senderContact)}/send';
  static String inboxMessage(int id) => '/api/integrations/inbox/$id';
  static String inboxCustomer(int id) => '/api/integrations/inbox/$id/customer';

  // Customers
  static const String customers = '/api/customers';
  static String customer(int id) => '/api/customers/$id';

  // Users
  static const String usersSearch = '/api/users/search';
  static const String usersMe = '/api/users/me';
  static String userByUsername(String username) => '/api/users/$username';

  // Integrations
  static const String integrationAccounts = '/api/integrations/accounts';


  // Telegram Integration
  static const String telegramConfig = '/api/integrations/telegram/config';
  static const String telegramGuide = '/api/integrations/telegram/guide';
  static const String telegramPhoneStart =
      '/api/integrations/telegram-phone/start';
  static const String telegramPhoneVerify =
      '/api/integrations/telegram-phone/verify';

  // WhatsApp Integration
  static const String whatsappConfig = '/api/integrations/whatsapp/config';
  static const String whatsappWebhook = '/api/integrations/whatsapp/webhook';

  // Preferences
  static const String preferences = '/api/preferences';

  // Features (including Quran & Athkar)
  static const String features = '/api/features';
  static const String quranProgress = '/api/quran/progress';
  static const String athkarProgress = '/api/athkar/progress';

  // Chat Features
  static String markRead(int messageId) =>
      '/api/integrations/inbox/$messageId/read';
  static String markConversationRead(String senderContact) =>
      '/api/integrations/conversations/${Uri.encodeComponent(senderContact)}/read';
  static String archiveConversation(String senderContact) =>
      '/api/integrations/conversations/${Uri.encodeComponent(senderContact)}/archive';
  static String togglePinConversation(String senderContact) =>
      '/api/integrations/conversations/${Uri.encodeComponent(senderContact)}/pin';
  static const String markAllAsRead = '/api/integrations/conversations/read-all';

  // Notifications
  static const String notifications = '/api/notifications';

  /// Web Push subscription (browser - requires endpoint, keys)
  static const String pushSubscribe = '/api/notifications/push/subscribe';

  /// FCM subscription (mobile - requires token, platform)
  static const String fcmSubscribe = '/api/notifications/push/mobile/register';

  /// FCM unsubscription (mobile - requires token)
  static const String fcmUnsubscribe =
      '/api/notifications/push/mobile/unregister';

  // Knowledge Base
  static const String knowledgeDocuments = '/api/knowledge/documents';
  static const String knowledgeUpload = '/api/knowledge/upload'; // Multipart

  // Export
  static const String exportData = '/api/export';

  // App Version
  static const String versionCheck = '/api/app/version-check';

  // Update Events (Analytics)
  static const String updateEvent = '/api/app/update-event';

  // Subscriptions (Admin)
  static const String subscriptionCreate = '/api/admin/subscription/create';
  static const String subscriptionList = '/api/admin/subscription/list';
  static String subscriptionDetail(int id) => '/api/admin/subscription/$id';
  static String subscriptionRegenerate(int id) =>
      '/api/admin/subscription/$id/regenerate-key';
  static String subscriptionUsage(int id) =>
      '/api/admin/subscription/usage/$id';

  // Library
  static const String libraryItems = '/api/library/';
  static const String libraryNote = '/api/library/notes';
  static const String libraryUpload = '/api/library/upload';
  static const String libraryBulkDelete = '/api/library/bulk-delete';
  static String libraryItem(int id) => '/api/library/$id';
  static const String libraryUsageStats = '/api/library/usage/statistics';

  // Stories
  static const String stories = '/api/stories';
  static const String storiesUpload = '/api/stories/upload';
  static const String storiesText = '/api/stories/text';
  static const String storiesViewsBatch = '/api/stories/views/batch';
  static const String storiesAnalytics = '/api/stories/analytics';
  static String storyView(int id) => '/api/stories/$id/view';
  static String storyViewers(int id) => '/api/stories/$id/viewers';
  static String storyViewCount(int id) => '/api/stories/$id/view-count';
  static String storyDelete(int id) => '/api/stories/$id';
  static const String storiesArchive = '/api/stories/archive';
  static const String storiesHighlights = '/api/stories/highlights';
  static String addStoryToHighlight(int storyId, int highlightId) =>
      '/api/stories/$storyId/highlight/$highlightId';
  static String removeStoryFromHighlight(int storyId, int highlightId) =>
      '/api/stories/$storyId/highlight/$highlightId';

  // Story Drafts
  static const String storiesDraft = '/api/stories/draft';
  
  // Story Search
  static const String storiesSearch = '/api/stories/search';
  
  // Story Export
  static const String storiesExport = '/api/stories/export';

  // Browser Tool
  static const String browserScrape = '/api/browser/scrape';
  static const String browserPreview = '/api/browser/preview';

  // Sync
  static const String syncBatch = '/api/v1/sync/batch';

  // Calculator History
  static const String calculatorHistory = '/api/calculator/history';
}
