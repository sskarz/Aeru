import Foundation
import Combine

struct ChatSession: Identifiable, Codable, Equatable {
    let id: String
    var title: String
    let collectionName: String
    let createdAt: Date
    var updatedAt: Date
    
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

class ChatSessionManager: ObservableObject {
    @Published var sessions: [ChatSession] = []
    @Published var currentSession: ChatSession?
    
    private let databaseManager = DatabaseManager.shared
    
    init() {
        loadSessions()
    }
    
    func loadSessions() {
        sessions = databaseManager.getAllChatSessions()
        if currentSession == nil && !sessions.isEmpty {
            currentSession = sessions.first
        }
    }
    
    func createNewSession(title: String = "New Chat") -> ChatSession? {
        guard let newSession = databaseManager.createChatSession(title: title) else {
            return nil
        }
        
        sessions.insert(newSession, at: 0)
        currentSession = newSession
        return newSession
    }
    
    func deleteSession(_ session: ChatSession) {
        databaseManager.deleteChatSession(session.id)
        sessions.removeAll { $0.id == session.id }
        
        if currentSession?.id == session.id {
            currentSession = sessions.first
        }
    }
    
    func updateSessionTitle(_ session: ChatSession, title: String) {
        var updatedSession = session
        updatedSession.title = title
        updatedSession.updatedAt = Date()
        
        databaseManager.updateChatSession(updatedSession)
        
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
        
        // Move to top of list
        sessions.removeAll { $0.id == session.id }
        sessions.insert(updatedSession, at: 0)
    }
}

