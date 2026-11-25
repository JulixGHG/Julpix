import SwiftUI

struct DashboardView: View {
    @EnvironmentObject var connectionManager: PcConnectionManager
    @EnvironmentObject var bgManager: BackgroundManager

    @State private var selectedTab: DashboardTab = .overview
    @State private var showAddPc = false
    @State private var showBgSettings = false

    enum DashboardTab: String, CaseIterable, Identifiable {
        case overview = "Übersicht"
        case compute = "CPU & GPU"
        case storageNet = "Speicher & Netz"
        case processes = "Prozesse"
        var id: String { rawValue }
    }

    var body: some View {
        ZStack {
            LiveBackgroundView()

            VStack(spacing: 10) {
                topBar

                if let stats = connectionManager.stats {
                    Group {
                        switch selectedTab {
                        case .overview:
                            overviewGrid(stats)
                        case .compute:
                            computeGrid(stats)
                        case .storageNet:
                            storageNetGrid(stats)
                        case .processes:
                            processesList(stats)
                        }
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    emptyOrConnectingView
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
        }
        .sheet(isPresented: $showAddPc) {
            AddPcSheet()
        }
        .sheet(isPresented: $showBgSettings) {
            BackgroundSettingsSheet()
        }
    }

    // MARK: - Top Navigation Bar (Landscape)

    private var topBar: some View {
        HStack(spacing: 12) {
            Button {
                showAddPc = true
            } label: {
                HStack(spacing: 8) {
                    Circle()
                        .fill(connectionManager.connectionState.isConnected ? Color.green : Color.orange)
                        .frame(width: 9, height: 9)
                    Text(connectionManager.activePc?.name ?? "PC hinzufügen")
                        .font(.subheadline.bold())
                        .foregroundColor(.white)
                    Image(systemName: "chevron.down")
                        .font(.caption2)
                        .foregroundColor(.white.opacity(0.7))
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 7)
                .background(Color.black.opacity(0.55))
                .cornerRadius(20)
                .overlay(Capsule().stroke(Color.white.opacity(0.18), lineWidth: 1))
            }

            HStack(spacing: 4) {
                ForEach(DashboardTab.allCases) { tab in
                    Button {
                        withAnimation(.easeInOut(duration: 0.2)) {
                            selectedTab = tab
                        }
                    } label: {
                        Text(tab.rawValue)
                            .font(.caption.bold())
                            .foregroundColor(selectedTab == tab ? .black : .white.opacity(0.85))
                            .padding(.horizontal, 12)
                            .padding(.vertical, 6)
                            .background(selectedTab == tab ? Color.cyan : Color.clear)
                            .cornerRadius(14)
                    }
                }
            }
            .padding(3)
            .background(Color.black.opacity(0.45))
            .cornerRadius(18)

            Spacer()

            Button {
                showBgSettings = true
            } label: {
                Label("Hintergrund", systemImage: "sparkles.tv")
                    .font(.caption.bold())
                    .foregroundColor(.white)
                    .padding(.horizontal, 11)
                    .padding(.vertical, 7)
                    .background(Color.purple.opacity(0.55))
                    .cornerRadius(16)
            }

            Button {
                showAddPc = true
            } label: {
                Image(systemName: "plus.circle.fill")
                    .font(.title3)
                    .foregroundColor(.cyan)
            }
        }
    }

    // MARK: - Empty / Waiting State

    private var emptyOrConnectingView: some View {
        GlassCard {
            VStack(spacing: 14) {
                Image(systemName: connectionManager.activePc == nil ? "desktopcomputer.and.arrow.down" : "wifi.exclamationmark")
                    .font(.system(size: 42))
                    .foregroundColor(.cyan)

                Text(connectionManager.activePc == nil
                     ? "Kein Windows-PC verbunden"
                     : "Status: \(connectionManager.connectionState.label)")
                    .font(.title3.bold())
                    .foregroundColor(.white)

                Text("Starte JulpixConnect auf deinem Windows-PC und füge ihn per QR-Code oder WLAN-Suche hinzu.")
                    .font(.caption)
                    .foregroundColor(.white.opacity(0.75))
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: 420)

                HStack(spacing: 12) {
                    Button {
                        showAddPc = true
                    } label: {
                        Label("PC hinzufügen", systemImage: "qrcode.viewfinder")
                            .font(.subheadline.bold())
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(.cyan)

                    if let pc = connectionManager.activePc {
                        Button {
                            connectionManager.connect(to: pc)
                        } label: {
                            Label("Erneut verbinden", systemImage: "arrow.clockwise")
                                .font(.subheadline.bold())
                        }
                        .buttonStyle(.bordered)
                    }
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    // MARK: - Tab 1: Overview (3-Column Landscape Grid)

    private func overviewGrid(_ stats: PcStatsPayload) -> some View {
        HStack(spacing: 12) {
            // Col 1: CPU
            GlassCard {
                VStack(alignment: .leading, spacing: 10) {
                    HStack {
                        Label("CPU", systemImage: "cpu")
                            .font(.caption.bold())
                            .foregroundColor(.cyan)
                        Spacer()
                        if let temp = stats.cpu.temperatureC {
                            Text("\(Int(temp))°C")
                                .font(.caption.bold())
                                .foregroundColor(temp > 80 ? .red : .orange)
                        }
                    }

                    Text(stats.cpu.name)
                        .font(.caption2)
                        .foregroundColor(.white.opacity(0.7))
                        .lineLimit(1)

                    HStack(spacing: 14) {
                        GaugeRingView(
                            progress: stats.cpu.usagePercent,
                            color: .cyan,
                            title: "AUSLASTUNG",
                            valueText: "\(Int(stats.cpu.usagePercent))%"
                        )
                        .frame(width: 86, height: 86)

                        VStack(alignment: .leading, spacing: 4) {
                            Text("\(stats.cpu.cores) Kerne / \(stats.cpu.threads) Threads")
                                .font(.caption2)
                                .foregroundColor(.white.opacity(0.8))
                            if let clock = stats.cpu.clockMhz {
                                Text(String(format: "%.2f GHz", clock / 1000.0))
                                    .font(.subheadline.bold())
                                    .foregroundColor(.white)
                            }
                            SparklineView(values: connectionManager.cpuHistory, color: .cyan, maxValue: 100)
                                .frame(height: 36)
                        }
                    }

                    Spacer(minLength: 0)
                }
            }

            // Col 2: GPU + RAM
            VStack(spacing: 12) {
                GlassCard {
                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            Label("GPU", systemImage: "display")
                                .font(.caption.bold())
                                .foregroundColor(.green)
                            Spacer()
                            if let temp = stats.gpu.temperatureC {
                                Text("\(Int(temp))°C")
                                    .font(.caption.bold())
                                    .foregroundColor(temp > 82 ? .red : .orange)
                            }
                        }

                        Text(stats.gpu.name)
                            .font(.caption2)
                            .foregroundColor(.white.opacity(0.7))
                            .lineLimit(1)

                        HStack(spacing: 12) {
                            GaugeRingView(
                                progress: stats.gpu.usagePercent ?? 0,
                                color: .green,
                                title: "GPU",
                                valueText: stats.gpu.usagePercent.map { "\(Int($0))%" } ?? "—"
                            )
                            .frame(width: 68, height: 68)

                            VStack(alignment: .leading, spacing: 4) {
                                if let used = stats.gpu.vramUsedMb, let total = stats.gpu.vramTotalMb, total > 0 {
                                    Text("VRAM: \(Int(used)) / \(Int(total)) MB")
                                        .font(.caption2)
                                        .foregroundColor(.white.opacity(0.85))
                                    ProgressView(value: used, total: total)
                                        .tint(.green)
                                }
                                if let fan = stats.gpu.fanPercent {
                                    Text("Lüfter: \(Int(fan))%")
                                        .font(.caption2)
                                        .foregroundColor(.white.opacity(0.7))
                                }
                            }
                        }
                    }
                }

                GlassCard {
                    VStack(alignment: .leading, spacing: 6) {
                        HStack {
                            Label("RAM", systemImage: "memorychip")
                                .font(.caption.bold())
                                .foregroundColor(.purple)
                            Spacer()
                            Text("\(Int(stats.memory.usagePercent))%")
                                .font(.subheadline.bold())
                                .foregroundColor(.white)
                        }
                        ProgressView(value: stats.memory.usagePercent, total: 100)
                            .tint(.purple)
                        HStack {
                            Text(String(format: "%.1f / %.1f GB", stats.memory.usedGb, stats.memory.totalGb))
                                .font(.caption2)
                                .foregroundColor(.white.opacity(0.8))
                            Spacer()
                            if let mhz = stats.memory.speedMhz {
                                Text("\(mhz) MHz")
                                    .font(.caption2)
                                    .foregroundColor(.white.opacity(0.65))
                            }
                        }
                    }
                }
            }

            // Col 3: Network + Disks & System
            VStack(spacing: 12) {
                GlassCard {
                    VStack(alignment: .leading, spacing: 6) {
                        HStack {
                            Label("NETZWERK", systemImage: "network")
                                .font(.caption.bold())
                                .foregroundColor(.yellow)
                            Spacer()
                            Text(stats.network.ipAddress)
                                .font(.caption2)
                                .foregroundColor(.white.opacity(0.65))
                        }

                        HStack {
                            Text("↓ \(StatsFormatter.rate(stats.network.downloadKbps))")
                                .font(.caption.bold())
                                .foregroundColor(.cyan)
                            Spacer()
                            Text("↑ \(StatsFormatter.rate(stats.network.uploadKbps))")
                                .font(.caption.bold())
                                .foregroundColor(.orange)
                        }

                        SparklineView(values: connectionManager.downHistory, color: .yellow)
                            .frame(height: 36)
                    }
                }

                GlassCard {
                    VStack(alignment: .leading, spacing: 6) {
                        HStack {
                            Label("SYSTEM & LAUFWERKE", systemImage: "internaldrive")
                                .font(.caption.bold())
                                .foregroundColor(.pink)
                            Spacer()
                            Text("Up: \(StatsFormatter.uptime(stats.system.uptimeSeconds))")
                                .font(.caption2)
                                .foregroundColor(.white.opacity(0.7))
                        }

                        ForEach(stats.disks.prefix(3)) { disk in
                            VStack(alignment: .leading, spacing: 2) {
                                HStack {
                                    Text("\(disk.name) \(disk.label)")
                                        .font(.caption2.bold())
                                        .lineLimit(1)
                                    Spacer()
                                    Text(String(format: "%.0f/%.0f GB", disk.usedGb, disk.totalGb))
                                        .font(.caption2)
                                        .foregroundColor(.white.opacity(0.75))
                                }
                                ProgressView(value: disk.usagePercent, total: 100)
                                    .tint(.pink)
                            }
                        }
                    }
                }
            }
        }
    }

    // MARK: - Tab 2: CPU & GPU Detailed

    private func computeGrid(_ stats: PcStatsPayload) -> some View {
        HStack(spacing: 12) {
            GlassCard {
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Text("CPU Kerne (\(stats.cpu.threads) Threads)")
                            .font(.subheadline.bold())
                            .foregroundColor(.cyan)
                        Spacer()
                        Text("\(Int(stats.cpu.usagePercent))%")
                            .font(.headline.bold())
                    }

                    ScrollView {
                        LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 8), count: 4), spacing: 8) {
                            ForEach(Array(stats.cpu.perCorePercent.enumerated()), id: \.offset) { idx, val in
                                VStack(alignment: .leading, spacing: 3) {
                                    HStack {
                                        Text("C\(idx)")
                                            .font(.caption2)
                                            .foregroundColor(.white.opacity(0.7))
                                        Spacer()
                                        Text("\(Int(val))%")
                                            .font(.caption2.bold())
                                    }
                                    ProgressView(value: val, total: 100)
                                        .tint(.cyan)
                                }
                                .padding(6)
                                .background(Color.white.opacity(0.06))
                                .cornerRadius(8)
                            }
                        }
                    }
                }
            }

            GlassCard {
                VStack(alignment: .leading, spacing: 10) {
                    Text("GPU Telemetrie")
                        .font(.subheadline.bold())
                        .foregroundColor(.green)

                    Text(stats.gpu.name)
                        .font(.caption)
                        .foregroundColor(.white.opacity(0.8))

                    SparklineView(values: connectionManager.gpuHistory, color: .green, maxValue: 100)
                        .frame(height: 80)

                    HStack {
                        statTile("Temperatur", stats.gpu.temperatureC.map { "\(Int($0))°C" } ?? "—")
                        statTile("Takt", stats.gpu.clockMhz.map { "\(Int($0)) MHz" } ?? "—")
                        statTile("Lüfter", stats.gpu.fanPercent.map { "\(Int($0))%" } ?? "—")
                    }
                    Spacer(minLength: 0)
                }
            }
        }
    }

    // MARK: - Tab 3: Storage & Network

    private func storageNetGrid(_ stats: PcStatsPayload) -> some View {
        HStack(spacing: 12) {
            GlassCard {
                VStack(alignment: .leading, spacing: 10) {
                    Text("Festplatten & SSDs")
                        .font(.subheadline.bold())
                        .foregroundColor(.pink)

                    ScrollView {
                        VStack(spacing: 10) {
                            ForEach(stats.disks) { disk in
                                VStack(alignment: .leading, spacing: 4) {
                                    HStack {
                                        Text("\(disk.name) (\(disk.label))")
                                            .font(.caption.bold())
                                        Spacer()
                                        Text(String(format: "%.1f / %.1f GB (%.0f%%)", disk.usedGb, disk.totalGb, disk.usagePercent))
                                            .font(.caption2)
                                            .foregroundColor(.white.opacity(0.8))
                                    }
                                    ProgressView(value: disk.usagePercent, total: 100)
                                        .tint(.pink)
                                    if disk.readKbps > 0 || disk.writeKbps > 0 {
                                        Text("Lesen: \(StatsFormatter.rate(disk.readKbps))  •  Schreiben: \(StatsFormatter.rate(disk.writeKbps))")
                                            .font(.caption2)
                                            .foregroundColor(.white.opacity(0.65))
                                    }
                                }
                                .padding(8)
                                .background(Color.white.opacity(0.06))
                                .cornerRadius(10)
                            }
                        }
                    }
                }
            }

            GlassCard {
                VStack(alignment: .leading, spacing: 10) {
                    Text("Netzwerk: \(stats.network.adapterName)")
                        .font(.subheadline.bold())
                        .foregroundColor(.yellow)

                    Text("Lokale IP: \(stats.network.ipAddress)")
                        .font(.caption)
                        .foregroundColor(.white.opacity(0.75))

                    HStack {
                        statTile("Download", StatsFormatter.rate(stats.network.downloadKbps))
                        statTile("Upload", StatsFormatter.rate(stats.network.uploadKbps))
                    }

                    SparklineView(values: connectionManager.downHistory, color: .cyan)
                        .frame(height: 60)
                    SparklineView(values: connectionManager.upHistory, color: .orange)
                        .frame(height: 45)
                }
            }
        }
    }

    // MARK: - Tab 4: Top Processes

    private func processesList(_ stats: PcStatsPayload) -> some View {
        GlassCard {
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text("Top Prozesse")
                        .font(.subheadline.bold())
                        .foregroundColor(.cyan)
                    Spacer()
                    Text("\(stats.system.hostname) • \(stats.system.os)")
                        .font(.caption2)
                        .foregroundColor(.white.opacity(0.7))
                }

                ScrollView {
                    VStack(spacing: 6) {
                        ForEach(stats.processes) { proc in
                            HStack {
                                Text(proc.name)
                                    .font(.caption.bold())
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                Text("PID \(proc.pid)")
                                    .font(.caption2)
                                    .foregroundColor(.white.opacity(0.6))
                                    .frame(width: 75, alignment: .trailing)
                                Text(String(format: "%.1f%% CPU", proc.cpuPercent))
                                    .font(.caption.bold())
                                    .foregroundColor(.cyan)
                                    .frame(width: 85, alignment: .trailing)
                                Text(String(format: "%.0f MB", proc.memoryMb))
                                    .font(.caption.bold())
                                    .foregroundColor(.purple)
                                    .frame(width: 80, alignment: .trailing)
                            }
                            .padding(.horizontal, 10)
                            .padding(.vertical, 6)
                            .background(Color.white.opacity(0.06))
                            .cornerRadius(8)
                        }
                    }
                }
            }
        }
    }

    private func statTile(_ title: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title)
                .font(.caption2)
                .foregroundColor(.white.opacity(0.65))
            Text(value)
                .font(.caption.bold())
                .foregroundColor(.white)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(8)
        .background(Color.white.opacity(0.07))
        .cornerRadius(8)
    }
}
