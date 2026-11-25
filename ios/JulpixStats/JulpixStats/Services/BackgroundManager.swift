import Foundation
import SwiftUI

@MainActor
final class BackgroundManager: ObservableObject {
    @Published var config: BackgroundConfig {
        didSet { saveConfig() }
    }

    private let configKey = "julpix_bg_config"

    var backgroundsDirectory: URL {
        let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        let dir = docs.appendingPathComponent("Backgrounds", isDirectory: true)
        if !FileManager.default.fileExists(atPath: dir.path) {
            try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        }
        return dir
    }

    var activeMediaUrl: URL? {
        guard let fileName = config.mediaFileName else { return nil }
        let url = backgroundsDirectory.appendingPathComponent(fileName)
        return FileManager.default.fileExists(atPath: url.path) ? url : nil
    }

    init() {
        if let data = UserDefaults.standard.data(forKey: configKey),
           let decoded = try? JSONDecoder().decode(BackgroundConfig.self, from: data) {
            self.config = decoded
        } else {
            self.config = BackgroundConfig()
        }
    }

    private func saveConfig() {
        if let data = try? JSONEncoder().encode(config) {
            UserDefaults.standard.set(data, forKey: configKey)
        }
    }

    func setEffect(_ effect: LiveEffectType) {
        config.mode = .effect
        config.effect = effect
    }

    func importMedia(from sourceUrl: URL, isGif: Bool) throws {
        let ext = sourceUrl.pathExtension.isEmpty ? (isGif ? "gif" : "mp4") : sourceUrl.pathExtension.lowercased()
        let fileName = "live_bg_\(Int(Date().timeIntervalSince1970)).\(ext)"
        let destUrl = backgroundsDirectory.appendingPathComponent(fileName)

        // Clean up old media files
        if let existing = try? FileManager.default.contentsOfDirectory(at: backgroundsDirectory, includingPropertiesForKeys: nil) {
            for item in existing {
                try? FileManager.default.removeItem(at: item)
            }
        }

        let needsSecurity = sourceUrl.startAccessingSecurityScopedResource()
        defer {
            if needsSecurity { sourceUrl.stopAccessingSecurityScopedResource() }
        }

        try FileManager.default.copyItem(at: sourceUrl, to: destUrl)
        config.mediaFileName = fileName
        config.mode = isGif || ext == "gif" ? .gif : .video
    }

    func importMediaData(_ data: Data, fileExtension: String, isGif: Bool) throws {
        let ext = fileExtension.lowercased()
        let fileName = "live_bg_\(Int(Date().timeIntervalSince1970)).\(ext)"
        let destUrl = backgroundsDirectory.appendingPathComponent(fileName)

        if let existing = try? FileManager.default.contentsOfDirectory(at: backgroundsDirectory, includingPropertiesForKeys: nil) {
            for item in existing {
                try? FileManager.default.removeItem(at: item)
            }
        }

        try data.write(to: destUrl)
        config.mediaFileName = fileName
        config.mode = isGif || ext == "gif" ? .gif : .video
    }
}
