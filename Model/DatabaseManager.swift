import Foundation
import SQLite

class DatabaseManager {
    static let shared = DatabaseManager()
    private var db: Connection?
    
    // Tables
    private let chatSessions = Table("chat_sessions")
    private let chatMessages = Table("chat_messages")
    
    // Chat Sessions columns
    private let sessionId = Expression<String>("id")
    private let sessionTitle = Expression<String>("title")
    private let sessionCollectionName = Expression<String>("collection_name")
    private let sessionCreatedAt = Expression<Date>("created_at")
    private let sessionUpdatedAt = Expression<Date>("updated_at")
    
    // Chat Messages columns
    private let messageId = Expression<String>("id")
    private let messageSessionId = Expression<String>("session_id")
    private let messageText = Expression<String>("text")
    private let messageIsUser = Expression<Bool>("is_user")
    private let messageTimestamp = Expression<Date>("timestamp")
    private let messageSources = Expression<String?>("sources") // JSON string for web sources
    
    private init() {
        setupDatabase()
    }
    
    private func setupDatabase() {
        do {
            let documentsPath = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!
            let dbPath = documentsPath.appendingPathComponent("chat_database.sqlite3").path
            db = try Connection(dbPath)
            createTables()
        } catch {
            print("Database setup error: \(error)")
        }
    }
    
    private func createTables() {
        do {
            // Create chat sessions table
            try db?.run(chatSessions.create(ifNotExists: true) { t in
                t.column(sessionId, primaryKey: true)
                t.column(sessionTitle)
                t.column(sessionCollectionName)
                t.column(sessionCreatedAt)
                t.column(sessionUpdatedAt)
            })
            
            // Create chat messages table
            try db?.run(chatMessages.create(ifNotExists: true) { t in
                t.column(messageId, primaryKey: true)
                t.column(messageSessionId)
                t.column(messageText)
                t.column(messageIsUser)
                t.column(messageTimestamp)
                t.column(messageSources)
                t.foreignKey(messageSessionId, references: chatSessions, sessionId, delete: .cascade)
            })
        } catch {
            print("Create tables error: \(error)")
        }
    }
    
    // MARK: - Chat Sessions
    
    func createChatSession(title: String) -> ChatSession? {
        let id = UUID().uuidString
        let collectionName = "chat_\(id)"
        let now = Date()
        
        do {
            let insert = chatSessions.insert(
                sessionId <- id,
                sessionTitle <- title,
                sessionCollectionName <- collectionName,
                sessionCreatedAt <- now,
                sessionUpdatedAt <- now
            )
            try db?.run(insert)
            
            return ChatSession(
                id: id,
                title: title,
                collectionName: collectionName,
                createdAt: now,
                updatedAt: now
            )
        } catch {
            print("Create chat session error: \(error)")
            return nil
        }
    }
    
    func getAllChatSessions() -> [ChatSession] {
        do {
            let sessions = try db?.prepare(chatSessions.order(sessionUpdatedAt.desc))
            return sessions?.compactMap { row in
                ChatSession(
                    id: row[sessionId],
                    title: row[sessionTitle],
                    collectionName: row[sessionCollectionName],
                    createdAt: row[sessionCreatedAt],
                    updatedAt: row[sessionUpdatedAt]
                )
            } ?? []
        } catch {
            print("Get all chat sessions error: \(error)")
            return []
        }
    }
    
    func updateChatSession(_ session: ChatSession) {
        do {
            let sessionRow = chatSessions.filter(sessionId == session.id)
            try db?.run(sessionRow.update(
                sessionTitle <- session.title,
                sessionUpdatedAt <- Date()
            ))
        } catch {
            print("Update chat session error: \(error)")
        }
    }
    
    func deleteChatSession(_ sessionId: String) {
        do {
            let sessionRow = chatSessions.filter(self.sessionId == sessionId)
            try db?.run(sessionRow.delete())
        } catch {
            print("Delete chat session error: \(error)")
        }
    }
    
    // MARK: - Chat Messages
    
    func saveMessage(_ message: ChatMessage, sessionId: String) {
        do {
            var sourcesString: String? = nil
            if let sources = message.sources, !sources.isEmpty {
                let sourcesData = try JSONEncoder().encode(sources)
                sourcesString = String(data: sourcesData, encoding: .utf8)
            }
            
            let insert = chatMessages.insert(
                messageId <- message.id.uuidString,
                messageSessionId <- sessionId,
                messageText <- message.text,
                messageIsUser <- message.isUser,
                messageTimestamp <- message.timestamp,
                messageSources <- sourcesString
            )
            try db?.run(insert)
        } catch {
            print("Save message error: \(error)")
        }
    }
    
    func getMessages(for sessionId: String) -> [ChatMessage] {
        do {
            let messages = try db?.prepare(
                chatMessages
                    .filter(messageSessionId == sessionId)
                    .order(messageTimestamp.asc)
            )
            
            return messages?.compactMap { row in
                var sources: [WebSearchResult]? = nil
                
                if let sourcesString = row[messageSources],
                   let sourcesData = sourcesString.data(using: .utf8) {
                    sources = try? JSONDecoder().decode([WebSearchResult].self, from: sourcesData)
                }
                
                return ChatMessage(
                    text: row[messageText],
                    isUser: row[messageIsUser],
                    sources: sources
                )
            } ?? []
        } catch {
            print("Get messages error: \(error)")
            return []
        }
    }
    
    func deleteAllMessages(for sessionId: String) {
        do {
            let sessionMessages = chatMessages.filter(messageSessionId == sessionId)
            try db?.run(sessionMessages.delete())
        } catch {
            print("Delete all messages error: \(error)")
        }
    }
}