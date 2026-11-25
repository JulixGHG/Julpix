import Foundation

struct SavedPc: Identifiable, Codable, Equatable {
    var id: UUID = UUID()
    var name: String
    var ip: String
    var port: Int
    var pin: String
}

struct DiscoveredPc: Identifiable, Hashable {
    var id: String { "\(ip):\(port)" }
    let name: String
    let ip: String
    let port: Int
}

struct QrPairingPayload: Codable {
    let app: String?
    let name: String
    let ip: String
    let port: Int
    let pin: String
}

struct PcStatsPayload: Codable {
    let type: String
    let timestamp: Int64
    let system: SystemStats
    let cpu: CpuStats
    let gpu: GpuStats
    let memory: MemoryStats
    let network: NetworkStats
    let disks: [DiskStats]
    let processes: [ProcessStats]
}

struct SystemStats: Codable {
    let hostname: String
    let os: String
    let uptimeSeconds: Int64
    let batteryPercent: Double?
    let isCharging: Bool
}

struct CpuStats: Codable {
    let name: String
    let usagePercent: Double
    let temperatureC: Double?
    let clockMhz: Double?
    let cores: Int
    let threads: Int
    let perCorePercent: [Double]
}

struct GpuStats: Codable {
    let name: String
    let usagePercent: Double?
    let temperatureC: Double?
    let vramUsedMb: Double?
    let vramTotalMb: Double?
    let fanPercent: Double?
    let clockMhz: Double?
}

struct MemoryStats: Codable {
    let usedGb: Double
    let totalGb: Double
    let availableGb: Double
    let usagePercent: Double
    let speedMhz: Int?
}

struct NetworkStats: Codable {
    let adapterName: String
    let ipAddress: String
    let downloadKbps: Double
    let uploadKbps: Double
}

struct DiskStats: Codable, Identifiable {
    var id: String { name }
    let name: String
    let label: String
    let usedGb: Double
    let totalGb: Double
    let usagePercent: Double
    let readKbps: Double
    let writeKbps: Double
}

struct ProcessStats: Codable, Identifiable {
    var id: Int { pid }
    let name: String
    let pid: Int
    let cpuPercent: Double
    let memoryMb: Double
}

enum LiveEffectType: String, CaseIterable, Codable, Identifiable {
    case cyberGrid = "Cyberpunk Grid"
    case particles = "Sternen-Partikel"
    case aurora = "Aurora Wellen"
    case matrix = "Matrix Regen"

    var id: String { rawValue }
}

enum BackgroundMode: String, Codable {
    case effect
    case video
    case gif
}

struct BackgroundConfig: Codable {
    var mode: BackgroundMode = .effect
    var effect: LiveEffectType = .cyberGrid
    var mediaFileName: String? = nil
    var dimOpacity: Double = 0.35
    var blurRadius: Double = 0.0
    var cardOpacity: Double = 0.55
}
