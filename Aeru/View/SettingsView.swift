//
//  SettingsView.swift
//  Aeru
//
//  Created by Sanskar
//

import SwiftUI
import Foundation

enum AppColorScheme: String, CaseIterable {
    case system = "System"
    case light = "Light"
    case dark = "Dark"
    
    var colorScheme: SwiftUI.ColorScheme? {
        switch self {
        case .system:
            return nil
        case .light:
            return .light
        case .dark:
            return .dark
        }
    }
}

struct SettingsView: View {
    @Environment(\.dismiss) private var dismiss
    @AppStorage("colorScheme") private var selectedColorScheme = AppColorScheme.system.rawValue
    
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
                
                // Appearance Section
                VStack(spacing: 16) {
                    Text("Appearance")
                        .font(.headline)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    
                    VStack(spacing: 12) {
                        HStack {
                            Text("Color Scheme")
                                .font(.body)
                                .foregroundColor(.primary)
                            
                            Spacer()
                            
                            Picker("Color Scheme", selection: $selectedColorScheme) {
                                ForEach(AppColorScheme.allCases, id: \.rawValue) { colorScheme in
                                    Text(colorScheme.rawValue).tag(colorScheme.rawValue)
                                }
                            }
                            .pickerStyle(MenuPickerStyle())
                        }
                        .padding(.horizontal, 16)
                        .padding(.vertical, 12)
                        .background(Color(.systemGray6))
                        .cornerRadius(8)
                    }
                }
                .padding(.horizontal, 20)
                
                // Links Section
                VStack(spacing: 16) {
                    Text("Community & Support")
                        .font(.headline)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    
                    VStack(spacing: 12) {
                        // GitHub Link
                        Button(action: {
                            if let url = URL(string: "https://github.com/sskarz/Aeru") {
                                UIApplication.shared.open(url)
                            }
                        }) {
                            HStack {
                                Image("github-logo")
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
                            if let url = URL(string: "https://discord.gg/RbWjUukHVV") {
                                UIApplication.shared.open(url)
                            }
                        }) {
                            HStack {
                                Image("discord-logo")
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
