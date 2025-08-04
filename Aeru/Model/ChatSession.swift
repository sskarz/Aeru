//
//  ChatSession.swift
//  Aeru
//
//  Created by Sanskar
//

import Foundation
import Combine

struct ChatSession: Identifiable, Codable, Equatable {
    let id: String
    var title: String
    let collectionName: String
    let createdAt: Date
    var updatedAt: Date
    var useWebSearch: Bool
    
    var displayTitle: String {
        title.isEmpty ? "New Chat" : title
    }
    
    var formattedDate: String {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        return formatter.string(from: updatedAt)
    }
}

enum SessionCreationResult {
    case success(ChatSession)
    case duplicateUntitled
    case duplicateTitle
    case databaseError
}

class ChatSessionManager: ObservableObject {
    @Published var sessions: [ChatSession] = []
    @Published var currentSession: ChatSession?
    
    private let databaseManager = DatabaseManager.shared
    
    init() {
        // Load sessions asynchronously to avoid blocking UI
        Task {
            await MainActor.run {
                loadSessions()
            }
        }
    }
    
    func loadSessions() {
        sessions = databaseManager.getAllChatSessions()
        if currentSession == nil && !sessions.isEmpty {
            currentSession = sessions.first
        }
    }
    
    func createNewSession(title: String = "") -> SessionCreationResult {
        // For empty titles, check if a "New Chat" session already exists
        let normalizedTitle = title.trimmingCharacters(in: .whitespacesAndNewlines)
        
        if normalizedTitle.isEmpty {
            // Check if there's already an empty-titled session (displays as "New Chat")
            if sessions.contains(where: { $0.title.isEmpty }) {
                return .duplicateUntitled
            }
        } else if titleExists(normalizedTitle) {
            return .duplicateTitle
        }
        
        guard let newSession = databaseManager.createChatSession(title: normalizedTitle, useWebSearch: false) else {
            return .databaseError
        }
        
        sessions.insert(newSession, at: 0)
        currentSession = newSession
        return .success(newSession)
    }
    
    // Convenience method for backward compatibility
    func tryCreateNewSession(title: String = "") -> ChatSession? {
        switch createNewSession(title: title) {
        case .success(let session):
            return session
        default:
            return nil
        }
    }
    
    func titleExists(_ title: String) -> Bool {
        let normalizedTitle = title.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        return sessions.contains { $0.title.lowercased() == normalizedTitle }
    }
    
    func deleteSession(_ session: ChatSession) {
        databaseManager.deleteChatSession(session.id)
        sessions.removeAll { $0.id == session.id }
        
        if currentSession?.id == session.id {
            currentSession = sessions.first
        }
    }
    
    func deleteSessions(_ sessionIds: Set<String>) {
        // Delete from database
        for sessionId in sessionIds {
            databaseManager.deleteChatSession(sessionId)
        }
        
        // Remove from sessions array
        sessions.removeAll { sessionIds.contains($0.id) }
        
        // Update current session if it was deleted
        if let current = currentSession, sessionIds.contains(current.id) {
            currentSession = sessions.first
        }
    }
    
    func updateSessionTitle(_ session: ChatSession, title: String) -> Bool {
        // Check for duplicate titles (excluding current session)
        let normalizedTitle = title.trimmingCharacters(in: .whitespacesAndNewlines)
        if sessions.contains(where: { $0.id != session.id && $0.title.lowercased() == normalizedTitle.lowercased() }) {
            return false
        }
        
        var updatedSession = session
        updatedSession.title = normalizedTitle
        updatedSession.updatedAt = Date()
        
        databaseManager.updateChatSession(updatedSession)
        
        if let index = sessions.firstIndex(where: { $0.id == session.id }) {
            sessions[index] = updatedSession
        }
        
        if currentSession?.id == session.id {
            currentSession = updatedSession
        }
        
        return true
    }
    
    func updateSessionTitleIfEmpty(_ session: ChatSession, with newTitle: String) {
        // Only update if the session currently has an empty title
        guard session.title.isEmpty else { 
            print("⚠️ SessionManager: Skipping title update - session already has title: '\(session.title)'")
            return 
        }
        
        print("🔄 SessionManager: Updating empty title to: '\(newTitle)' for session: \(session.id)")
        
        var updatedSession = session
        updatedSession.title = newTitle.trimmingCharacters(in: .whitespacesAndNewlines)
        updatedSession.updatedAt = Date()
        
        databaseManager.updateChatSession(updatedSession)
        print("💾 SessionManager: Updated session in database")
        
        if let index = sessions.firstIndex(where: { $0.id == session.id }) {
            sessions[index] = updatedSession
            print("📝 SessionManager: Updated session in sessions array at index \(index)")
        }
        
        if currentSession?.id == session.id {
            currentSession = updatedSession
            print("✅ SessionManager: Updated currentSession with new title")
        }
    }
    
    func updateSessionWebSearch(_ session: ChatSession, useWebSearch: Bool) {
        var updatedSession = session
        updatedSession.useWebSearch = useWebSearch
        updatedSession.updatedAt = Date()
        
        databaseManager.updateChatSessionWebSearch(session.id, useWebSearch: useWebSearch)
        
        if let index = sessions.firstIndex(where: { $0.id == session.id }) {
            sessions[index] = updatedSession
        }
        
        if currentSession?.id == session.id {
            currentSession = updatedSession
        }
    }
    
    func selectSession(_ session: ChatSession) {
        currentSession = session
        
        // Update the session's updatedAt time when accessed
        var updatedSession = session
        updatedSession.updatedAt = Date()
        databaseManager.updateChatSession(updatedSession)
        
        if let index = sessions.firstIndex(where: { $0.id == session.id }) {
            sessions[index] = updatedSession
        }
        
        // Keep the chat in its current position - removed repositioning logic
    }
}

