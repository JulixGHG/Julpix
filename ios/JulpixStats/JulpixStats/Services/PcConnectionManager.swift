import Foundation
import UIKit

@MainActor
final class PcConnectionManager: ObservableObject {
    @Published var savedPcs: [SavedPc] = []
    @Published var activePcId: UUID?
    @Published var stats: PcStatsPayload?
    @Published var connectionState: ConnectionState = .disconnected
    @Published var discoveredPcs: [DiscoveredPc] = []
    @Published var isDiscovering: Bool = false

    @Published var cpuHistory: [Double] = []
    @Published var gpuHistory: [Double] = []
    @Published var downHistory: [Double] = []
    @Published var upHistory: [Double] = []

    enum ConnectionState: Equatable {
        case disconnected
        case connecting
        case connected
        case error(String)

        var label: String {
            switch self {
            case .disconnected: return "Getrennt"
            case .connecting: return "Verbinde..."
            case .connected: return "Verbunden"
            case .error(let msg): return msg
            }
        }

        var isConnected: Bool {
            if case .connected = self { return true }
            return false
        }
    }

    private let savedPcsKey = "julpix_saved_pcs"
    private let activePcKey = "julpix_active_pc_id"

    private var webSocketTask: URLSessionWebSocketTask?
    private var urlSession: URLSession?
    private var reconnectTask: Task<Void, Never>?
    private var manualDisconnect = false

    var activePc: SavedPc? {
        savedPcs.first(where: { $0.id == activePcId })
    }

    init() {
        loadSavedPcs()
        if let activePc {
            connect(to: activePc)
        }
    }

    private func loadSavedPcs() {
        if let data = UserDefaults.standard.data(forKey: savedPcsKey),
           let decoded = try? JSONDecoder().decode([SavedPc].self, from: data) {
            savedPcs = decoded
        }
        if let idStr = UserDefaults.standard.string(forKey: activePcKey),
           let uuid = UUID(uuidString: idStr),
           savedPcs.contains(where: { $0.id == uuid }) {
            activePcId = uuid
        } else {
            activePcId = savedPcs.first?.id
        }
    }

    private func persistSavedPcs() {
        if let data = try? JSONEncoder().encode(savedPcs) {
            UserDefaults.standard.set(data, forKey: savedPcsKey)
        }
        UserDefaults.standard.set(activePcId?.uuidString, forKey: activePcKey)
    }

    func addOrUpdatePc(_ pc: SavedPc) {
        if let idx = savedPcs.firstIndex(where: { $0.ip == pc.ip && $0.port == pc.port }) {
            var updated = pc
            updated.id = savedPcs[idx].id
            savedPcs[idx] = updated
            activePcId = updated.id
        } else {
            savedPcs.append(pc)
            activePcId = pc.id
        }
        persistSavedPcs()
        if let target = activePc {
            connect(to: target)
        }
    }

    func removePc(_ pc: SavedPc) {
        savedPcs.removeAll { $0.id == pc.id }
        if activePcId == pc.id {
            disconnect()
            activePcId = savedPcs.first?.id
            if let next = activePc {
                connect(to: next)
            }
        }
        persistSavedPcs()
    }

    func selectPc(_ pc: SavedPc) {
        activePcId = pc.id
        persistSavedPcs()
        connect(to: pc)
    }

    func connect(to pc: SavedPc) {
        disconnect(keepManualFlag: false)
        manualDisconnect = false
        connectionState = .connecting
        clearHistories()

        let deviceName = UIDevice.current.name.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? "iPhone"
        let pinEncoded = pc.pin.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? pc.pin
        guard let url = URL(string: "ws://\(pc.ip):\(pc.port)/ws?pin=\(pinEncoded)&device=\(deviceName)") else {
            connectionState = .error("Ungültige Adresse")
            return
        }

        let config = URLSessionConfiguration.default
        config.waitsForConnectivity = false
        let session = URLSession(configuration: config)
        urlSession = session

        let task = session.webSocketTask(with: url)
        webSocketTask = task
        task.resume()

        receiveNextMessage(for: task, pc: pc)
    }

    func disconnect(keepManualFlag: Bool = true) {
        if keepManualFlag {
            manualDisconnect = true
        }
        reconnectTask?.cancel()
        reconnectTask = nil
        webSocketTask?.cancel(with: .goingAway, reason: nil)
        webSocketTask = nil
        urlSession?.invalidateAndCancel()
        urlSession = nil
        connectionState = .disconnected
    }

    private func receiveNextMessage(for task: URLSessionWebSocketTask, pc: SavedPc) {
        task.receive { [weak self] result in
            Task { @MainActor [weak self] in
                guard let self, self.webSocketTask === task else { return }
                switch result {
                case .success(let message):
                    self.connectionState = .connected
                    if case .string(let text) = message,
                       let data = text.data(using: .utf8),
                       let decoded = try? JSONDecoder().decode(PcStatsPayload.self, from: data) {
                        self.stats = decoded
                        self.appendHistories(decoded)
                    }
                    self.receiveNextMessage(for: task, pc: pc)

                case .failure(let error):
                    let msg = error.localizedDescription
                    if msg.contains("403") || msg.localizedCaseInsensitiveContains("bad response") {
                        self.connectionState = .error("Falscher PIN oder abgelehnt")
                        return
                    }
                    self.connectionState = .error("Verbindung verloren")
                    self.scheduleReconnect(pc: pc)
                }
            }
        }
    }

    private func scheduleReconnect(pc: SavedPc) {
        guard !manualDisconnect else { return }
        reconnectTask?.cancel()
        reconnectTask = Task {
            try? await Task.sleep(nanoseconds: 3_000_000_000)
            guard !Task.isCancelled, !manualDisconnect, activePcId == pc.id else { return }
            connect(to: pc)
        }
    }

    private func appendHistories(_ payload: PcStatsPayload) {
        let maxPoints = 30
        cpuHistory.append(payload.cpu.usagePercent)
        if cpuHistory.count > maxPoints { cpuHistory.removeFirst() }

        gpuHistory.append(payload.gpu.usagePercent ?? 0)
        if gpuHistory.count > maxPoints { gpuHistory.removeFirst() }

        downHistory.append(payload.network.downloadKbps)
        if downHistory.count > maxPoints { downHistory.removeFirst() }

        upHistory.append(payload.network.uploadKbps)
        if upHistory.count > maxPoints { upHistory.removeFirst() }
    }

    private func clearHistories() {
        cpuHistory.removeAll()
        gpuHistory.removeAll()
        downHistory.removeAll()
        upHistory.removeAll()
        stats = nil
    }

    // MARK: - LAN Discovery (UDP 52841 + HTTP /health Subnet Scan on 52840)

    func discoverLocalPcs() {
        isDiscovering = true
        discoveredPcs = []

        Task.detached { [weak self] in
            async let udpResults = Self.performUdpBroadcastDiscovery()
            async let httpResults = Self.performHttpSubnetDiscovery()

            var combined = await udpResults
            for item in await httpResults where !combined.contains(item) {
                combined.append(item)
            }

            await MainActor.run {
                self?.discoveredPcs = combined
                self?.isDiscovering = false
            }
        }
    }

    private nonisolated static func performHttpSubnetDiscovery() async -> [DiscoveredPc] {
        guard let wifiIp = getWifiIPv4Address() else { return [] }
        let parts = wifiIp.split(separator: ".")
        guard parts.count == 4 else { return [] }
        let prefix = "\(parts[0]).\(parts[1]).\(parts[2])"

        let config = URLSessionConfiguration.ephemeral
        config.timeoutIntervalForRequest = 0.7
        config.timeoutIntervalForResource = 0.8
        let session = URLSession(configuration: config)

        return await withTaskGroup(of: DiscoveredPc?.self) { group in
            for host in 1...254 {
                let candidateIp = "\(prefix).\(host)"
                if candidateIp == wifiIp { continue }
                group.addTask {
                    guard let url = URL(string: "http://\(candidateIp):52840/health") else { return nil }
                    do {
                        let (data, response) = try await session.data(from: url)
                        guard let http = response as? HTTPURLResponse, http.statusCode == 200,
                              let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                              (obj["app"] as? String) == "JulpixConnect",
                              let name = obj["name"] as? String else { return nil }
                        let port = (obj["port"] as? Int) ?? 52840
                        return DiscoveredPc(name: name, ip: candidateIp, port: port)
                    } catch {
                        return nil
                    }
                }
            }

            var found: [DiscoveredPc] = []
            for await item in group {
                if let item, !found.contains(item) {
                    found.append(item)
                }
            }
            return found
        }
    }

    private nonisolated static func getWifiIPv4Address() -> String? {
        var ifaddr: UnsafeMutablePointer<ifaddrs>?
        guard getifaddrs(&ifaddr) == 0, let firstAddr = ifaddr else { return nil }
        defer { freeifaddrs(ifaddr) }

        for ptr in sequence(first: firstAddr, next: { $0.pointee.ifa_next }) {
            let interface = ptr.pointee
            let addrFamily = interface.ifa_addr.pointee.sa_family
            if addrFamily == UInt8(AF_INET) {
                let name = String(cString: interface.ifa_name)
                if name == "en0" || name == "en1" {
                    var hostname = [CChar](repeating: 0, count: Int(NI_MAXHOST))
                    getnameinfo(interface.ifa_addr, socklen_t(interface.ifa_addr.pointee.sa_len),
                                &hostname, socklen_t(hostname.count), nil, 0, NI_NUMERICHOST)
                    return String(cString: hostname)
                }
            }
        }
        return nil
    }

    private nonisolated static func performUdpBroadcastDiscovery() -> [DiscoveredPc] {
        var results: [DiscoveredPc] = []
        let fd = socket(AF_INET, SOCK_DGRAM, IPPROTO_UDP)
        guard fd >= 0 else { return results }
        defer { close(fd) }

        var broadcastEnable: Int32 = 1
        setsockopt(fd, SOL_SOCKET, SO_BROADCAST, &broadcastEnable, socklen_t(MemoryLayout<Int32>.size))

        var timeout = timeval(tv_sec: 1, tv_usec: 500_000)
        setsockopt(fd, SOL_SOCKET, SO_RCVTIMEO, &timeout, socklen_t(MemoryLayout<timeval>.size))

        var addr = sockaddr_in()
        addr.sin_len = UInt8(MemoryLayout<sockaddr_in>.size)
        addr.sin_family = sa_family_t(AF_INET)
        addr.sin_port = in_port_t(52841).bigEndian
        addr.sin_addr.s_addr = inet_addr("255.255.255.255")

        let probe = Array("JULPIX_DISCOVER".utf8)
        _ = withUnsafePointer(to: &addr) {
            $0.withMemoryRebound(to: sockaddr.self, capacity: 1) { sockPtr in
                sendto(fd, probe, probe.count, 0, sockPtr, socklen_t(MemoryLayout<sockaddr_in>.size))
            }
        }

        var buffer = [UInt8](repeating: 0, count: 1024)
        var senderAddr = sockaddr_in()
        var senderLen = socklen_t(MemoryLayout<sockaddr_in>.size)

        for _ in 0..<8 {
            let received = withUnsafeMutablePointer(to: &senderAddr) {
                $0.withMemoryRebound(to: sockaddr.self, capacity: 1) { sockPtr in
                    recvfrom(fd, &buffer, buffer.count, 0, sockPtr, &senderLen)
                }
            }
            if received <= 0 { break }

            let data = Data(bytes: buffer, count: received)
            if let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
               let name = obj["name"] as? String,
               let ip = obj["ip"] as? String,
               let port = obj["port"] as? Int {
                let item = DiscoveredPc(name: name, ip: ip, port: port)
                if !results.contains(item) {
                    results.append(item)
                }
            }
        }

        return results
    }
}
