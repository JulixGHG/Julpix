import PhotosUI
import SwiftUI
import UniformTypeIdentifiers

struct BackgroundSettingsSheet: View {
    @EnvironmentObject var bgManager: BackgroundManager
    @Environment(\.dismiss) var dismiss

    @State private var selectedPhotoItem: PhotosPickerItem?
    @State private var showFileImporter = false
    @State private var statusMessage: String?

    var body: some View {
        NavigationStack {
            HStack(spacing: 18) {
                // Left: Source Selection
                VStack(alignment: .leading, spacing: 14) {
                    Text("Eingebaute Live-Effekte")
                        .font(.headline)

                    LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 10) {
                        ForEach(LiveEffectType.allCases) { effect in
                            let isSelected = bgManager.config.mode == .effect && bgManager.config.effect == effect
                            Button {
                                bgManager.setEffect(effect)
                            } label: {
                                HStack {
                                    Image(systemName: isSelected ? "checkmark.circle.fill" : "sparkles")
                                    Text(effect.rawValue)
                                        .font(.caption.bold())
                                        .lineLimit(1)
                                }
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 10)
                                .padding(.horizontal, 8)
                                .background(isSelected ? Color.cyan.opacity(0.35) : Color.white.opacity(0.08))
                                .cornerRadius(10)
                                .overlay(
                                    RoundedRectangle(cornerRadius: 10)
                                        .stroke(isSelected ? Color.cyan : Color.clear, lineWidth: 1.5)
                                )
                            }
                            .buttonStyle(.plain)
                        }
                    }

                    Divider()

                    Text("Eigenes Live-Hintergrundbild (ohne iPhone Live-Photo)")
                        .font(.headline)

                    HStack(spacing: 10) {
                        PhotosPicker(selection: $selectedPhotoItem, matching: .any(of: [.videos, .images])) {
                            Label("Aus Fotos (Video/GIF)", systemImage: "photo.on.rectangle")
                                .font(.caption.bold())
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 10)
                        }
                        .buttonStyle(.borderedProminent)
                        .tint(.purple)

                        Button {
                            showFileImporter = true
                        } label: {
                            Label("Aus Dateien (MP4/GIF)", systemImage: "folder")
                                .font(.caption.bold())
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 10)
                        }
                        .buttonStyle(.bordered)
                    }

                    if let statusMessage {
                        Text(statusMessage)
                            .font(.caption)
                            .foregroundColor(.green)
                    }

                    Spacer()
                }
                .frame(maxWidth: .infinity)

                Divider()

                // Right: Visual Tuning
                VStack(alignment: .leading, spacing: 16) {
                    Text("Darstellung anpassen")
                        .font(.headline)

                    VStack(alignment: .leading, spacing: 4) {
                        HStack {
                            Text("Abdunkeln")
                            Spacer()
                            Text("\(Int(bgManager.config.dimOpacity * 100))%")
                                .foregroundColor(.secondary)
                        }
                        .font(.caption)
                        Slider(value: $bgManager.config.dimOpacity, in: 0...0.85)
                    }

                    VStack(alignment: .leading, spacing: 4) {
                        HStack {
                            Text("Hintergrund-Unschärfe")
                            Spacer()
                            Text("\(Int(bgManager.config.blurRadius))")
                                .foregroundColor(.secondary)
                        }
                        .font(.caption)
                        Slider(value: $bgManager.config.blurRadius, in: 0...25)
                    }

                    VStack(alignment: .leading, spacing: 4) {
                        HStack {
                            Text("Karten-Deckkraft")
                            Spacer()
                            Text("\(Int(bgManager.config.cardOpacity * 100))%")
                                .foregroundColor(.secondary)
                        }
                        .font(.caption)
                        Slider(value: $bgManager.config.cardOpacity, in: 0.15...0.9)
                    }

                    Spacer()
                }
                .frame(maxWidth: .infinity)
            }
            .padding()
            .navigationTitle("Live-Hintergrund")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Fertig") { dismiss() }
                }
            }
            .onChange(of: selectedPhotoItem) { newItem in
                guard let newItem else { return }
                Task {
                    await handlePickedPhotoItem(newItem)
                }
            }
            .fileImporter(
                isPresented: $showFileImporter,
                allowedContentTypes: [.mpeg4Movie, .quickTimeMovie, .movie, .gif],
                allowsMultipleSelection: false
            ) { result in
                if case .success(let urls) = result, let url = urls.first {
                    do {
                        let isGif = url.pathExtension.lowercased() == "gif"
                        try bgManager.importMedia(from: url, isGif: isGif)
                        statusMessage = isGif ? "GIF-Hintergrund aktiv!" : "Video-Hintergrund aktiv!"
                    } catch {
                        statusMessage = "Fehler: \(error.localizedDescription)"
                    }
                }
            }
        }
    }

    private func handlePickedPhotoItem(_ item: PhotosPickerItem) async {
        do {
            if let data = try await item.loadTransferable(type: Data.self) {
                let isGif = item.supportedContentTypes.contains(UTType.gif)
                let ext = isGif ? "gif" : "mp4"
                try bgManager.importMediaData(data, fileExtension: ext, isGif: isGif)
                statusMessage = isGif ? "GIF aus Fotos geladen!" : "Video aus Fotos geladen!"
            }
        } catch {
            statusMessage = "Konnte Medium nicht laden: \(error.localizedDescription)"
        }
    }
}
