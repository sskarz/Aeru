import SwiftUI
import Foundation


struct ChatSidebar: View {
    @ObservedObject var sessionManager: ChatSessionManager
    @State private var showingNewChatAlert = false
    @State private var newChatTitle = ""
    @State private var editingSession: ChatSession?
    @State private var editTitle = ""
    @State private var showingDuplicateTitleAlert = false
    @State private var showingEditDuplicateTitleAlert = false
    @State private var isSelectionMode = false
    @State private var selectedSessions: Set<String> = []
    @State private var showingBulkDeleteAlert = false
    @State private var showingSettings = false
    
    var body: some View {
        VStack(spacing: 0) {
            // Header
            VStack(spacing: 12) {
                HStack {
                    if isSelectionMode {
                        Button("Cancel") {
                            isSelectionMode = false
                            selectedSessions.removeAll()
                        }
                        .font(.body)
                        .foregroundColor(.blue)
                        
                        Spacer()
                        
                        Text("\(selectedSessions.count) selected")
                            .font(.body)
                            .foregroundColor(.secondary)
                        
                        Spacer()
                        
                        Button(action: { showingBulkDeleteAlert = true }) {
                            Image(systemName: "trash")
                                .font(.title3)
                                .foregroundColor(selectedSessions.isEmpty ? .gray : .red)
                        }
                        .disabled(selectedSessions.isEmpty)
                    } else {
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
                            isSelectionMode: isSelectionMode,
                            isChecked: selectedSessions.contains(session.id),
                            onSelect: {
                                if isSelectionMode {
                                    if selectedSessions.contains(session.id) {
                                        selectedSessions.remove(session.id)
                                    } else {
                                        selectedSessions.insert(session.id)
                                    }
                                } else {
                                    sessionManager.selectSession(session)
                                }
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
            
            // Bottom controls
            VStack(spacing: 0) {
                Divider()
                
                HStack {
                    Button(action: { showingSettings = true }) {
                        HStack {
                            Image(systemName: "gear")
                                .font(.title3)
                                .foregroundColor(.blue)
                            
                            Text("Settings")
                                .font(.body)
                                .foregroundColor(.blue)
                        }
                    }
                    .buttonStyle(.plain)
                    
                    Spacer()
                    
                    Button(action: { 
                        isSelectionMode = true 
                    }) {
                        Image(systemName: "checkmark.circle")
                            .font(.title3)
                            .foregroundColor(.blue)
                            .frame(width: 24, height: 24)
                    }
                    .buttonStyle(.plain)
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 16)
            }
        }
        .background(Color(.systemBackground))
        .alert("New Chat", isPresented: $showingNewChatAlert) {
            TextField("Chat title", text: $newChatTitle)
            Button("Create") {
                if !newChatTitle.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    if sessionManager.createNewSession(title: newChatTitle) != nil {
                        newChatTitle = ""
                    } else {
                        showingDuplicateTitleAlert = true
                    }
                } else {
                    _ = sessionManager.createNewSession()
                    newChatTitle = ""
                }
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
                    if sessionManager.updateSessionTitle(session, title: editTitle) {
                        editingSession = nil
                        editTitle = ""
                    } else {
                        showingEditDuplicateTitleAlert = true
                    }
                }
            }
            Button("Cancel", role: .cancel) {
                editingSession = nil
                editTitle = ""
            }
        } message: {
            Text("Edit the title for this chat session")
        }
        .alert("Duplicate Title", isPresented: $showingDuplicateTitleAlert) {
            Button("OK") {
                showingDuplicateTitleAlert = false
            }
        } message: {
            Text("A chat with this title already exists. Please choose a different title.")
        }
        .alert("Duplicate Title", isPresented: $showingEditDuplicateTitleAlert) {
            Button("OK") {
                showingEditDuplicateTitleAlert = false
            }
        } message: {
            Text("A chat with this title already exists. Please choose a different title.")
        }
        .alert("Delete Chats", isPresented: $showingBulkDeleteAlert) {
            Button("Delete", role: .destructive) {
                sessionManager.deleteSessions(selectedSessions)
                selectedSessions.removeAll()
                isSelectionMode = false
            }
            Button("Cancel", role: .cancel) { }
        } message: {
            Text("Are you sure you want to delete \(selectedSessions.count) chat\(selectedSessions.count == 1 ? "" : "s")? This action cannot be undone.")
        }
        .sheet(isPresented: $showingSettings) {
            SettingsView()
        }
    }
}

struct ChatSessionRow: View {
    let session: ChatSession
    let isSelected: Bool
    let isSelectionMode: Bool
    let isChecked: Bool
    let onSelect: () -> Void
    let onEdit: () -> Void
    let onDelete: () -> Void
    
    @State private var showingDeleteAlert = false
    
    var body: some View {
        HStack {
            if isSelectionMode {
                Button(action: onSelect) {
                    Image(systemName: isChecked ? "checkmark.circle.fill" : "circle")
                        .font(.system(size: 20))
                        .foregroundColor(isChecked ? .blue : .gray)
                }
                .buttonStyle(.plain)
            }
            
            VStack(alignment: .leading, spacing: 4) {
                Text(session.displayTitle)
                    .font(.system(size: 14, weight: .medium))
                    .foregroundColor(isSelected && !isSelectionMode ? .white : .primary)
                    .lineLimit(1)
                
                Text(session.formattedDate)
                    .font(.caption2)
                    .foregroundColor(isSelected && !isSelectionMode ? .white.opacity(0.8) : .secondary)
            }
            
            Spacer()
            
            if !isSelectionMode {
                Menu {
                    Button("Edit Title") {
                        onEdit()
                    }
                    
                    Button("Delete", role: .destructive) {
                        showingDeleteAlert = true
                    }
                } label: {
                    Image(systemName: "ellipsis")
                        .font(.system(size: 16, weight: .medium))
                        .foregroundColor(isSelected ? .white.opacity(0.8) : .secondary)
                        .frame(width: 32, height: 32)
                        .contentShape(Rectangle())
                }
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(isSelected && !isSelectionMode ? Color.blue : Color.clear)
        )
        .contentShape(Rectangle())
        .onTapGesture {
            if !isSelectionMode {
                onSelect()
            }
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

struct SettingsView: View {
    @Environment(\.dismiss) private var dismiss
    
    var body: some View {
        NavigationView {
            VStack(spacing: 24) {
                VStack(spacing: 16) {
                    // App Info Section
                    VStack(spacing: 8) {
                        Text("Aeru")
                            .font(.title)
                            .fontWeight(.bold)
                        
                        Text("AI Chat Assistant")
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                    }
                    .padding(.top, 20)
                }
                
                // Links Section
                VStack(spacing: 16) {
                    Text("Community & Support")
                        .font(.headline)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    
                    VStack(spacing: 12) {
                        // GitHub Link
                        Button(action: {
                            // You can fill in the GitHub URL here
                            if let url = URL(string: "https://github.com/sskarz/Aeru") {
                                UIApplication.shared.open(url)
                            }
                        }) {
                            HStack {
                                Image("github-logo") // You'll add this to Assets
                                    .resizable()
                                    .frame(width: 24, height: 24)
                                    .foregroundColor(.primary)
                                
                                Text("GitHub")
                                    .font(.body)
                                    .foregroundColor(.primary)
                                
                                Spacer()
                                
                                Image(systemName: "arrow.up.right")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }
                            .padding(.horizontal, 16)
                            .padding(.vertical, 12)
                            .background(Color(.systemGray6))
                            .cornerRadius(8)
                        }
                        .buttonStyle(.plain)
                        
                        // Discord Link
                        Button(action: {
                            // You can fill in the Discord URL here
                            if let url = URL(string: "https://discord.gg/mZY5fHXZ") {
                                UIApplication.shared.open(url)
                            }
                        }) {
                            HStack {
                                Image("discord-logo") // You'll add this to Assets
                                    .resizable()
                                    .frame(width: 24, height: 24)
                                    .foregroundColor(.primary)
                                
                                Text("Discord")
                                    .font(.body)
                                    .foregroundColor(.primary)
                                
                                Spacer()
                                
                                Image(systemName: "arrow.up.right")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }
                            .padding(.horizontal, 16)
                            .padding(.vertical, 12)
                            .background(Color(.systemGray6))
                            .cornerRadius(8)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal, 20)
                
                Spacer()
            }
            .navigationTitle("Settings")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Done") {
                        dismiss()
                    }
                }
            }
        }
    }
}
