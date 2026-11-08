import '../core/models.dart';

/// Storage contract used by [AppState].
///
/// Keeping this abstract makes the generation queue testable without a real
/// SQLite database.
abstract class ChatStore {
  Future<List<ChatThread>> listChats();

  Future<ChatThread> createChat(String id, DateTime now);

  Future<void> renameChat(String id, String title, DateTime now);

  Future<void> touchChat(String id, DateTime now);

  Future<void> deleteChat(String id);

  Future<List<ChatMessage>> messagesForChat(String chatId);

  Future<void> insertMessage(ChatMessage message);

  Future<void> deleteMessage(String id);

  Future<List<ChatMessage>> pendingMessages();
}
