import SwiftUI
import Foundation

struct ModelsTab: View {
    @StateObject private var settings = SettingsManager.shared
    @StateObject private var modelManager = ModelManager.shared
    
    @State private var showDeleteConfirmation = false
    @State private var modelToDelete: ModelInfo?
    @State private var showLowDiskSpaceAlert = false
    @State private var diskSpaceError: String = ""
    
    private let minimumDiskSpace: UInt64 = 1024 * 1024 * 1024 // 1GB in bytes
    
    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            // Header
            HStack {
                Image(systemName: "brain.head.profile")
                    .font(.system(size: 32))
                    .foregroundColor(.purple)
                    .accessibilityLabel("Models settings icon")
                
                VStack(alignment: .leading) {
                    Text("Model Management")
                        .font(.title2)
                        .fontWeight(.bold)
                    Text("Download and manage Whisper models")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
            .padding(.bottom, 10)
            
            Divider()
            
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    // Storage Overview
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Storage Usage")
                            .font(.headline)
                            .accessibilityAddTraits(.isHeader)
                        
                        HStack {
                            VStack(alignment: .leading, spacing: 4) {
                                HStack {
                                    Text("Models Storage:")
                                        .font(.caption)
                                        .foregroundColor(.secondary)
                                    Text(formatBytes(modelManager.totalStorageUsed))
                                        .font(.caption)
                                        .fontWeight(.medium)
                                }
                                
                                HStack {
                                    Text("Available Space:")
                                        .font(.caption)
                                        .foregroundColor(.secondary)
                                    Text(formatBytes(modelManager.availableDiskSpace))
                                        .font(.caption)
                                        .fontWeight(.medium)
                                        .foregroundColor(modelManager.availableDiskSpace < minimumDiskSpace ? .red : .primary)
                                }
                            }
                            
                            Spacer()
                            
                            if modelManager.availableDiskSpace < minimumDiskSpace {
                                Image(systemName: "exclamationmark.triangle.fill")
                                    .foregroundColor(.orange)
                                    .font(.system(size: 16))
                                    .accessibilityLabel("Low disk space warning")
                            }
                        }
                        .padding(12)
                        .background(Color(.controlBackgroundColor))
                        .cornerRadius(8)
                        
                        if modelManager.availableDiskSpace < minimumDiskSpace {
                            Text("Warning: Low disk space available. Free up space before downloading models.")
                                .font(.caption)
                                .foregroundColor(.orange)
                        }
                    }
                    
                    // Active Model Selection
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Active Model")
                            .font(.headline)
                            .accessibilityAddTraits(.isHeader)
                        
                        Picker("Select active model", selection: $modelManager.activeModelName) {
                            ForEach(modelManager.installedModels, id: \.name) { model in
                                HStack {
                                    Text(model.displayName)
                                    Spacer()
                                    Text("(\(formatBytes(model.fileSize)))")
                                        .font(.caption)
                                        .foregroundColor(.secondary)
                                }
                                .tag(model.name)
                            }
                        }
                        .pickerStyle(.menu)
                        .disabled(modelManager.installedModels.isEmpty)
                        .accessibilityLabel("Active model selection")
                        .accessibilityHint("Choose which model to use for voice transcription")
                        
                        Text("Requires app restart to take effect")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                    
                    // Available Models List
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Available Models")
                            .font(.headline)
                            .accessibilityAddTraits(.isHeader)
                        
                        LazyVStack(spacing: 8) {
                            ForEach(modelManager.availableModels, id: \.name) { model in
                                ModelRowView(
                                    model: model,
                                    onDownload: {
                                        if modelManager.availableDiskSpace < model.downloadSize {
                                            diskSpaceError = "Insufficient disk space to download \(model.displayName). Need \(formatBytes(model.downloadSize)), but only \(formatBytes(modelManager.availableDiskSpace)) available."
                                            showLowDiskSpaceAlert = true
                                        } else {
                                            Task {
                                                await modelManager.downloadModel(model)
                                            }
                                        }
                                    },
                                    onDelete: {
                                        modelToDelete = model
                                        showDeleteConfirmation = true
                                    },
                                    onRetry: {
                                        Task {
                                            await modelManager.retryDownload(model)
                                        }
                                    }
                                )
                            }
                        }
                    }
                }
            }
            
            Spacer()
        }
        .padding(20)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(Color(.windowBackgroundColor))
        .onAppear {
            Task {
                await modelManager.refreshModels()
                await modelManager.updateDiskSpace()
            }
        }
        .alert("Delete Model", isPresented: $showDeleteConfirmation) {
            Button("Delete", role: .destructive) {
                if let model = modelToDelete {
                    Task {
                        await modelManager.deleteModel(model)
                    }
                }
                modelToDelete = nil
            }
            Button("Cancel", role: .cancel) {
                modelToDelete = nil
            }
        } message: {
            if let model = modelToDelete {
                Text("Are you sure you want to delete \(model.displayName)? This will free up \(formatBytes(model.fileSize)) of storage space.")
            }
        }
        .alert("Insufficient Disk Space", isPresented: $showLowDiskSpaceAlert) {
            Button("OK", role: .cancel) { }
        } message: {
            Text(diskSpaceError)
        }
    }
    
    private func formatBytes(_ bytes: UInt64) -> String {
        let formatter = ByteCountFormatter()
        formatter.allowedUnits = [.useMB, .useGB]
        formatter.countStyle = .file
        return formatter.string(fromByteCount: Int64(bytes))
    }
}

// MARK: - Supporting Views

struct ModelRowView: View {
    let model: ModelInfo
    let onDownload: () -> Void
    let onDelete: () -> Void
    let onRetry: () -> Void
    
    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text(model.displayName)
                        .font(.subheadline)
                        .fontWeight(.medium)
                    
                    if model.status == .bundled {
                        Text("BUNDLED")
                            .font(.caption2)
                            .fontWeight(.bold)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(Color.blue.opacity(0.2))
                            .foregroundColor(.blue)
                            .cornerRadius(4)
                    }
                }
                
                Text(model.description)
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .lineLimit(2)
                
                HStack {
                    Text("Size: \(formatBytes(model.downloadSize))")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                    
                    if model.status == .installed {
                        Text("• Installed")
                            .font(.caption2)
                            .foregroundColor(.green)
                    }
                }
            }
            
            Spacer()
            
            VStack(alignment: .trailing, spacing: 8) {
                switch model.status {
                case .available:
                    Button("Download") {
                        onDownload()
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.small)
                    .accessibilityLabel("Download \(model.displayName)")
                    .accessibilityHint("Downloads the \(model.displayName) model for voice transcription")
                    
                case .downloading:
                    VStack(spacing: 4) {
                        ProgressView(value: model.downloadProgress)
                            .progressViewStyle(LinearProgressViewStyle())
                            .frame(width: 80)
                        
                        Text("\(Int(model.downloadProgress * 100))%")
                            .font(.caption2)
                            .foregroundColor(.secondary)
                    }
                    .accessibilityLabel("Downloading \(model.displayName), \(Int(model.downloadProgress * 100)) percent complete")
                    
                case .installed:
                    Button("Delete") {
                        onDelete()
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                    .accessibilityLabel("Delete \(model.displayName)")
                    .accessibilityHint("Removes the \(model.displayName) model from storage")
                    
                case .bundled:
                    Text("Built-in")
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .accessibilityLabel("\(model.displayName) is bundled with the app")
                    
                case .failed:
                    VStack(spacing: 4) {
                        Button("Retry") {
                            onRetry()
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                        .accessibilityLabel("Retry download of \(model.displayName)")
                        .accessibilityHint("Attempts to download the \(model.displayName) model again")
                        
                        Text("Failed")
                            .font(.caption2)
                            .foregroundColor(.red)
                    }
                }
            }
        }
        .padding(12)
        .background(Color(.controlBackgroundColor))
        .cornerRadius(8)
    }
    
    private func formatBytes(_ bytes: UInt64) -> String {
        let formatter = ByteCountFormatter()
        formatter.allowedUnits = [.useMB, .useGB]
        formatter.countStyle = .file
        return formatter.string(fromByteCount: Int64(bytes))
    }
}

#Preview {
    ModelsTab()
        .frame(width: 480, height: 320)
}