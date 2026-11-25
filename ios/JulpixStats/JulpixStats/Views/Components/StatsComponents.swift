import SwiftUI

struct GlassCard<Content: View>: View {
    @EnvironmentObject var bgManager: BackgroundManager
    let content: Content

    init(@ViewBuilder content: () -> Content) {
        self.content = content()
    }

    var body: some View {
        content
            .padding(14)
            .background(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(Color.black.opacity(bgManager.config.cardOpacity))
                    .background(
                        RoundedRectangle(cornerRadius: 16, style: .continuous)
                            .fill(.ultraThinMaterial)
                            .opacity(0.65)
                    )
            )
            .overlay(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .stroke(Color.white.opacity(0.14), lineWidth: 1)
            )
    }
}

struct GaugeRingView: View {
    let progress: Double
    let color: Color
    let title: String
    let valueText: String

    var body: some View {
        ZStack {
            Circle()
                .stroke(Color.white.opacity(0.12), lineWidth: 8)

            Circle()
                .trim(from: 0, to: min(1.0, max(0.0, progress / 100.0)))
                .stroke(
                    AngularGradient(colors: [color.opacity(0.7), color], center: .center),
                    style: StrokeStyle(lineWidth: 8, lineCap: .round)
                )
                .rotationEffect(.degrees(-90))
                .animation(.easeOut(duration: 0.35), value: progress)

            VStack(spacing: 1) {
                Text(valueText)
                    .font(.system(size: 17, weight: .bold, design: .rounded))
                    .foregroundColor(.white)
                Text(title)
                    .font(.system(size: 10, weight: .medium))
                    .foregroundColor(.white.opacity(0.65))
            }
        }
    }
}

struct SparklineView: View {
    let values: [Double]
    let color: Color
    var maxValue: Double? = nil

    var body: some View {
        GeometryReader { geo in
            let upper = max(1.0, maxValue ?? (values.max() ?? 100.0))
            if values.count >= 2 {
                let stepX = geo.size.width / CGFloat(values.count - 1)
                let points = values.enumerated().map { idx, val in
                    let x = CGFloat(idx) * stepX
                    let y = geo.size.height - CGFloat(min(1.0, max(0.0, val / upper))) * geo.size.height
                    return CGPoint(x: x, y: y)
                }

                ZStack {
                    Path { path in
                        path.move(to: CGPoint(x: 0, y: geo.size.height))
                        for pt in points { path.addLine(to: pt) }
                        path.addLine(to: CGPoint(x: geo.size.width, y: geo.size.height))
                        path.closeSubpath()
                    }
                    .fill(
                        LinearGradient(
                            colors: [color.opacity(0.35), color.opacity(0.02)],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    )

                    Path { path in
                        path.move(to: points[0])
                        for pt in points.dropFirst() { path.addLine(to: pt) }
                    }
                    .stroke(color, style: StrokeStyle(lineWidth: 2, lineCap: .round, lineJoin: .round))
                }
            } else {
                Rectangle()
                    .fill(Color.white.opacity(0.05))
                    .cornerRadius(6)
            }
        }
    }
}

enum StatsFormatter {
    static func rate(_ kbps: Double) -> String {
        if kbps >= 1024 {
            return String(format: "%.1f MB/s", kbps / 1024.0)
        }
        return String(format: "%.0f KB/s", kbps)
    }

    static func uptime(_ seconds: Int64) -> String {
        let days = seconds / 86400
        let hours = (seconds % 86400) / 3600
        let mins = (seconds % 3600) / 60
        if days > 0 { return "\(days)d \(hours)h \(mins)m" }
        return "\(hours)h \(mins)m"
    }
}
