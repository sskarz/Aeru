//
//  DatabaseManager.swift
//  Aeru
//
//  Created by Sanskar
//

import Foundation
import SQLite

class DatabaseManager {
    static let shared = DatabaseManager()
    private var db: Connection?
    
    // Tables
    private let chatSessions = Table("chat_sessions")
    private let chatMessages = Table("chat_messages")
    private let documents = Table("documents")
    private let documentChunks = Table("document_chunks")
    
    // Chat Sessions columns
    private let sessionId = Expression<String>("id")
    private let sessionTitle = Expression<String>("title")
    private let sessionCollectionName = Expression<String>("collection_name")
    private let sessionCreatedAt = Expression<Date>("created_at")
    private let sessionUpdatedAt = Expression<Date>("updated_at")
    private let sessionUseWebSearch = Expression<Bool>("use_web_search")
    
    // Chat Messages columns
    private let messageId = Expression<String>("id")
    private let messageSessionId = Expression<String>("session_id")
    private let messageText = Expression<String>("text")
    private let messageIsUser = Expression<Bool>("is_user")
    private let messageTimestamp = Expression<Date>("timestamp")
    private let messageSources = Expression<String?>("sources") // JSON string for web sources
    
    // Documents columns
    private let documentId = Expression<String>("id")
    private let documentSessionId = Expression<String>("session_id")
    private let documentName = Expression<String>("name")
    private let documentPath = Expression<String>("path")
    private let documentType = Expression<String>("type")
    private let documentUploadedAt = Expression<Date>("uploaded_at")
    
    // Document Chunks columns
    private let chunkId = Expression<String>("id")
    private let chunkDocumentId = Expression<String>("document_id")
    private let chunkText = Expression<String>("text")
    private let chunkIndex = Expression<Int>("chunk_index")
    private let chunkEmbedded = Expression<Bool>("embedded")
    
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
                t.column(sessionUseWebSearch, defaultValue: false)
            })
            
            // Migration: Add use_web_search column if it doesn't exist
            migrateAddWebSearchColumn()
            
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
            
            // Create documents table
            try db?.run(documents.create(ifNotExists: true) { t in
                t.column(documentId, primaryKey: true)
                t.column(documentSessionId)
                t.column(documentName)
                t.column(documentPath)
                t.column(documentType)
                t.column(documentUploadedAt)
                t.foreignKey(documentSessionId, references: chatSessions, sessionId, delete: .cascade)
            })
            
            // Create document chunks table
            try db?.run(documentChunks.create(ifNotExists: true) { t in
                t.column(chunkId, primaryKey: true)
                t.column(chunkDocumentId)
                t.column(chunkText)
                t.column(chunkIndex)
                t.column(chunkEmbedded, defaultValue: false)
                t.foreignKey(chunkDocumentId, references: documents, documentId, delete: .cascade)
            })
        } catch {
            print("Create tables error: \(error)")
        }
    }
    
    private func migrateAddWebSearchColumn() {
        do {
            // Check if the column exists by attempting to add it
            // If it fails, the column likely already exists
            try db?.run("ALTER TABLE chat_sessions ADD COLUMN use_web_search BOOLEAN DEFAULT 0")
            print("✅ Migration: Added use_web_search column to chat_sessions table")
        } catch {
            // Column likely already exists or other error - this is expected for existing databases
            print("📋 Migration: use_web_search column migration skipped (likely already exists)")
        }
    }
    
    // MARK: - Chat Sessions
    
    func createChatSession(title: String, useWebSearch: Bool = false) -> ChatSession? {
        let id = UUID().uuidString
        let collectionName = "chat_\(id)"
        let now = Date()
        
        do {
            let insert = chatSessions.insert(
                sessionId <- id,
                sessionTitle <- title,
                sessionCollectionName <- collectionName,
                sessionCreatedAt <- now,
                sessionUpdatedAt <- now,
                sessionUseWebSearch <- useWebSearch
            )
            try db?.run(insert)
            
            return ChatSession(
                id: id,
                title: title,
                collectionName: collectionName,
                createdAt: now,
                updatedAt: now,
                useWebSearch: useWebSearch
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
                    updatedAt: row[sessionUpdatedAt],
                    useWebSearch: row[sessionUseWebSearch]
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
                sessionUpdatedAt <- Date(),
                sessionUseWebSearch <- session.useWebSearch
            ))
        } catch {
            print("Update chat session error: \(error)")
        }
    }
    
    func updateChatSessionWebSearch(_ sessionId: String, useWebSearch: Bool) {
        do {
            let sessionRow = chatSessions.filter(self.sessionId == sessionId)
            try db?.run(sessionRow.update(
                sessionUseWebSearch <- useWebSearch,
                sessionUpdatedAt <- Date()
            ))
        } catch {
            print("Update chat session web search error: \(error)")
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
    
    // MARK: - Documents
    
    func saveDocument(sessionId: String, name: String, path: String, type: String) -> String? {
        let id = UUID().uuidString
        
        do {
            let insert = documents.insert(
                documentId <- id,
                documentSessionId <- sessionId,
                documentName <- name,
                documentPath <- path,
                documentType <- type,
                documentUploadedAt <- Date()
            )
            try db?.run(insert)
            return id
        } catch {
            print("Save document error: \(error)")
            return nil
        }
    }
    
    func getDocuments(for sessionId: String) -> [(id: String, name: String, type: String, uploadedAt: Date)] {
        do {
            let docs = try db?.prepare(
                documents
                    .filter(documentSessionId == sessionId)
                    .order(documentUploadedAt.desc)
            )
            
            return docs?.map { row in
                (id: row[documentId], name: row[documentName], type: row[documentType], uploadedAt: row[documentUploadedAt])
            } ?? []
        } catch {
            print("Get documents error: \(error)")
            return []
        }
    }
    
    func saveDocumentChunk(documentId: String, text: String, index: Int) -> String? {
        let id = UUID().uuidString
        
        do {
            let insert = documentChunks.insert(
                chunkId <- id,
                chunkDocumentId <- documentId,
                chunkText <- text,
                chunkIndex <- index,
                chunkEmbedded <- false
            )
            try db?.run(insert)
            return id
        } catch {
            print("Save document chunk error: \(error)")
            return nil
        }
    }
    
    func getUnembeddedChunks(for sessionId: String) -> [(id: String, text: String)] {
        do {
            let chunks = try db?.prepare(
                documentChunks
                    .join(documents, on: chunkDocumentId == documentId)
                    .filter(documentSessionId == sessionId && chunkEmbedded == false)
                    .order(chunkIndex.asc)
            )
            
            return chunks?.map { row in
                (id: row[chunkId], text: row[chunkText])
            } ?? []
        } catch {
            print("Get unembedded chunks error: \(error)")
            return []
        }
    }
    
    func markChunkAsEmbedded(_ chunkId: String) {
        do {
            let chunk = documentChunks.filter(self.chunkId == chunkId)
            try db?.run(chunk.update(chunkEmbedded <- true))
        } catch {
            print("Mark chunk as embedded error: \(error)")
        }
    }
}