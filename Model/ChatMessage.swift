import Foundation

struct ChatMessage: Identifiable {
    let id = UUID()
    let text: String
    let isUser: Bool
    let sources: [WebSearchResult]?
    let timestamp: Date
    
    init(text: String, isUser: Bool, sources: [WebSearchResult]? = nil) {
        self.text = text
        self.isUser = isUser
        self.sources = sources
        self.timestamp = Date()
    }
}