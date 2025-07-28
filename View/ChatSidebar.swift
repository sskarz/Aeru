import SwiftUI
import Foundation

struct ChatSidebar: View {
    @ObservedObject var sessionManager: ChatSessionManager
    @State private var showingNewChatAlert = false
    @State private var newChatTitle = ""
    @State private var editingSession: ChatSession?
    @State private var editTitle = ""
    
    var body: some View {
        VStack(spacing: 0) {
            // Header
            VStack(spacing: 12) {
                HStack {
                    Text("Chats")
                        .font(.title2)
                        .fontWeight(.semibold)
                    
                    Spacer()
                    
                    Button(action: { showingNewChatAlert = true }) {
                        Image(systemName: "plus")
                            .font(.title3)
                            .foregroundColor(.blue)
                            .frame(width: 24, height: 24)
                    }
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 16)
                
                Divider()
            }
            
            // Chat sessions list
            ScrollView {
                LazyVStack(spacing: 6) {
                    ForEach(sessionManager.sessions) { session in
                        ChatSessionRow(
                            session: session,
                            isSelected: sessionManager.currentSession?.id == session.id,
                            onSelect: {
                                sessionManager.selectSession(session)
                            },
                            onEdit: {
                                editingSession = session
                                editTitle = session.title
                            },
                            onDelete: {
                                sessionManager.deleteSession(session)
                            }
                        )
                    }
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 12)
            }
            .frame(maxHeight: .infinity)
        }
        .background(Color(.systemBackground))
        .alert("New Chat", isPresented: $showingNewChatAlert) {
            TextField("Chat title", text: $newChatTitle)
            Button("Create") {
                if !newChatTitle.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    _ = sessionManager.createNewSession(title: newChatTitle)
                } else {
                    _ = sessionManager.createNewSession()
                }
                newChatTitle = ""
            }
            Button("Cancel", role: .cancel) {
                newChatTitle = ""
            }
        } message: {
            Text("Enter a title for your new chat session")
        }
        .alert("Edit Chat Title", isPresented: Binding<Bool>(
            get: { editingSession != nil },
            set: { _ in editingSession = nil }
        )) {
            TextField("Chat title", text: $editTitle)
            Button("Save") {
                if let session = editingSession {
                    sessionManager.updateSessionTitle(session, title: editTitle)
                }
                editingSession = nil
                editTitle = ""
            }
            Button("Cancel", role: .cancel) {
                editingSession = nil
                editTitle = ""
            }
        } message: {
            Text("Edit the title for this chat session")
        }
    }
}

struct ChatSessionRow: View {
    let session: ChatSession
    let isSelected: Bool
    let onSelect: () -> Void
    let onEdit: () -> Void
    let onDelete: () -> Void
    
    @State private var showingDeleteAlert = false
    
    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                Text(session.displayTitle)
                    .font(.system(size: 14, weight: .medium))
                    .foregroundColor(isSelected ? .white : .primary)
                    .lineLimit(1)
                
                Text(session.formattedDate)
                    .font(.caption2)
                    .foregroundColor(isSelected ? .white.opacity(0.8) : .secondary)
            }
            
            Spacer()
            
            Menu {
                Button("Edit Title") {
                    onEdit()
                }
                
                Button("Delete", role: .destructive) {
                    showingDeleteAlert = true
                }
            } label: {
                Image(systemName: "ellipsis")
                    .font(.caption)
                    .foregroundColor(isSelected ? .white.opacity(0.8) : .secondary)
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(isSelected ? Color.blue : Color.clear)
        )
        .contentShape(Rectangle())
        .onTapGesture {
            onSelect()
        }
        .alert("Delete Chat", isPresented: $showingDeleteAlert) {
            Button("Delete", role: .destructive) {
                onDelete()
            }
            Button("Cancel", role: .cancel) { }
        } message: {
            Text("Are you sure you want to delete this chat? This action cannot be undone.")
        }
    }
}
