import AVFoundation
import ImageIO
import SwiftUI
import UIKit

struct LiveBackgroundView: View {
    @EnvironmentObject var bgManager: BackgroundManager

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            switch bgManager.config.mode {
            case .effect:
                BuiltInLiveEffectView(effect: bgManager.config.effect)
                    .ignoresSafeArea()
            case .video:
                if let url = bgManager.activeMediaUrl {
                    LoopingVideoPlayerView(url: url)
                        .ignoresSafeArea()
                } else {
                    BuiltInLiveEffectView(effect: bgManager.config.effect)
                        .ignoresSafeArea()
                }
            case .gif:
                if let url = bgManager.activeMediaUrl {
                    AnimatedGifView(url: url)
                        .ignoresSafeArea()
                } else {
                    BuiltInLiveEffectView(effect: bgManager.config.effect)
                        .ignoresSafeArea()
                }
            }

            if bgManager.config.blurRadius > 0.5 {
                Rectangle()
                    .fill(.ultraThinMaterial)
                    .opacity(min(1.0, bgManager.config.blurRadius / 25.0))
                    .ignoresSafeArea()
            }

            Color.black
                .opacity(bgManager.config.dimOpacity)
                .ignoresSafeArea()
        }
    }
}

// MARK: - Built-in 60fps Live Effects (no Live Photo needed)

struct BuiltInLiveEffectView: View {
    let effect: LiveEffectType

    var body: some View {
        TimelineView(.animation) { timeline in
            let t = timeline.date.timeIntervalSinceReferenceDate
            Canvas { context, size in
                switch effect {
                case .cyberGrid:
                    drawCyberGrid(context: context, size: size, t: t)
                case .particles:
                    drawParticles(context: context, size: size, t: t)
                case .aurora:
                    drawAurora(context: context, size: size, t: t)
                case .matrix:
                    drawMatrix(context: context, size: size, t: t)
                }
            }
        }
    }

    private func drawCyberGrid(context: GraphicsContext, size: CGSize, t: TimeInterval) {
        let bg = Gradient(colors: [Color(red: 0.03, green: 0.02, blue: 0.12), Color(red: 0.08, green: 0.02, blue: 0.18), Color.black])
        context.fill(Path(CGRect(origin: .zero, size: size)), with: .linearGradient(bg, startPoint: .zero, endPoint: CGPoint(x: 0, y: size.height)))

        let horizonY = size.height * 0.42
        let scroll = (t * 0.6).truncatingRemainder(dividingBy: 1.0)

        // Horizon glow
        let glowRect = CGRect(x: 0, y: horizonY - 40, width: size.width, height: 80)
        context.fill(Path(glowRect), with: .linearGradient(
            Gradient(colors: [.clear, Color.cyan.opacity(0.35), Color.purple.opacity(0.35), .clear]),
            startPoint: CGPoint(x: 0, y: horizonY - 40),
            endPoint: CGPoint(x: 0, y: horizonY + 40)
        ))

        // Vertical perspective lines
        let centerX = size.width / 2
        for i in -12...12 {
            var p = Path()
            let topX = centerX + CGFloat(i) * 28
            let bottomX = centerX + CGFloat(i) * 145
            p.move(to: CGPoint(x: topX, y: horizonY))
            p.addLine(to: CGPoint(x: bottomX, y: size.height))
            context.stroke(p, with: .color(Color.cyan.opacity(0.32)), lineWidth: 1)
        }

        // Horizontal moving lines
        for i in 0..<14 {
            let progress = (Double(i) + scroll) / 14.0
            let eased = progress * progress
            let y = horizonY + CGFloat(eased) * (size.height - horizonY)
            var p = Path()
            p.move(to: CGPoint(x: 0, y: y))
            p.addLine(to: CGPoint(x: size.width, y: y))
            context.stroke(p, with: .color(Color.pink.opacity(0.15 + eased * 0.35)), lineWidth: 1.2)
        }
    }

    private func drawParticles(context: GraphicsContext, size: CGSize, t: TimeInterval) {
        context.fill(Path(CGRect(origin: .zero, size: size)), with: .color(Color(red: 0.03, green: 0.05, blue: 0.1)))

        for i in 0..<55 {
            let seed = Double(i) * 1.6180339
            let xFrac = (sin(seed * 7.3) * 0.5 + 0.5 + t * (0.015 + Double(i % 5) * 0.005)).truncatingRemainder(dividingBy: 1.0)
            let yFrac = (cos(seed * 4.1) * 0.5 + 0.5 + sin(t * 0.4 + seed) * 0.04).truncatingRemainder(dividingBy: 1.0)
            let radius = CGFloat(2.0 + Double(i % 6) * 1.4)
            let x = CGFloat(xFrac) * size.width
            let y = CGFloat(abs(yFrac)) * size.height

            let color: Color = i % 3 == 0 ? .cyan : (i % 3 == 1 ? .blue : .purple)
            let rect = CGRect(x: x - radius, y: y - radius, width: radius * 2, height: radius * 2)
            context.fill(Path(ellipseIn: rect), with: .color(color.opacity(0.45)))
        }
    }

    private func drawAurora(context: GraphicsContext, size: CGSize, t: TimeInterval) {
        context.fill(Path(CGRect(origin: .zero, size: size)), with: .color(Color(red: 0.02, green: 0.04, blue: 0.08)))

        let colors: [Color] = [.green.opacity(0.28), .cyan.opacity(0.26), .purple.opacity(0.22)]
        for layer in 0..<3 {
            var path = Path()
            let baseY = size.height * (0.35 + Double(layer) * 0.16)
            path.move(to: CGPoint(x: 0, y: size.height))
            for x in stride(from: 0.0, through: Double(size.width), by: 16.0) {
                let wave = sin(x * 0.006 + t * (0.6 + Double(layer) * 0.2) + Double(layer)) * 45.0
                let wave2 = cos(x * 0.011 - t * 0.4) * 25.0
                path.addLine(to: CGPoint(x: x, y: baseY + wave + wave2))
            }
            path.addLine(to: CGPoint(x: size.width, y: size.height))
            path.closeSubpath()
            context.fill(path, with: .color(colors[layer]))
        }
    }

    private func drawMatrix(context: GraphicsContext, size: CGSize, t: TimeInterval) {
        context.fill(Path(CGRect(origin: .zero, size: size)), with: .color(Color(red: 0.01, green: 0.04, blue: 0.02)))
        let cols = Int(size.width / 22)
        for c in 0..<max(1, cols) {
            let speed = 60.0 + Double((c * 37) % 90)
            let offset = Double((c * 91) % 400)
            let headY = (t * speed + offset).truncatingRemainder(dividingBy: Double(size.height + 160)) - 80
            let x = CGFloat(c) * 22 + 8

            for step in 0..<8 {
                let y = CGFloat(headY) - CGFloat(step) * 16
                let alpha = max(0, 0.75 - Double(step) * 0.09)
                let rect = CGRect(x: x, y: y, width: 6, height: 11)
                context.fill(Path(roundedRect: rect, cornerRadius: 2), with: .color(Color.green.opacity(alpha)))
            }
        }
    }
}

// MARK: - Looping Video Player (MP4/MOV)

struct LoopingVideoPlayerView: UIViewRepresentable {
    let url: URL

    func makeCoordinator() -> Coordinator { Coordinator() }

    func makeUIView(context: Context) -> PlayerContainerView {
        let view = PlayerContainerView()
        context.coordinator.configure(url: url, in: view)
        return view
    }

    func updateUIView(_ uiView: PlayerContainerView, context: Context) {
        if context.coordinator.currentUrl != url {
            context.coordinator.configure(url: url, in: uiView)
        }
    }

    final class Coordinator {
        var currentUrl: URL?
        private var looper: AVPlayerLooper?
        private var queuePlayer: AVQueuePlayer?

        func configure(url: URL, in view: PlayerContainerView) {
            currentUrl = url
            let item = AVPlayerItem(url: url)
            let player = AVQueuePlayer(playerItem: item)
            player.isMuted = true
            player.allowsExternalPlayback = false
            let looper = AVPlayerLooper(player: player, templateItem: item)

            self.queuePlayer = player
            self.looper = looper
            view.playerLayer.player = player
            view.playerLayer.videoGravity = .resizeAspectFill
            player.play()
        }
    }

    final class PlayerContainerView: UIView {
        override class var layerClass: AnyClass { AVPlayerLayer.self }
        var playerLayer: AVPlayerLayer { layer as! AVPlayerLayer }
    }
}

// MARK: - Animated GIF View (ImageIO)

struct AnimatedGifView: UIViewRepresentable {
    let url: URL

    func makeUIView(context: Context) -> UIImageView {
        let imageView = UIImageView()
        imageView.contentMode = .scaleAspectFill
        imageView.clipsToBounds = true
        loadGif(into: imageView, from: url)
        return imageView
    }

    func updateUIView(_ uiView: UIImageView, context: Context) {
        loadGif(into: uiView, from: url)
    }

    private func loadGif(into imageView: UIImageView, from url: URL) {
        guard let data = try? Data(contentsOf: url),
              let source = CGImageSourceCreateWithData(data as CFData, nil) else { return }

        let count = CGImageSourceGetCount(source)
        var images: [UIImage] = []
        var totalDuration: Double = 0

        for i in 0..<count {
            if let cgImage = CGImageSourceCreateImageAtIndex(source, i, nil) {
                images.append(UIImage(cgImage: cgImage))
            }
            let props = CGImageSourceCopyPropertiesAtIndex(source, i, nil) as? [String: Any]
            let gifProps = props?[kCGImagePropertyGIFDictionary as String] as? [String: Any]
            let delay = (gifProps?[kCGImagePropertyGIFUnclampedDelayTime as String] as? Double)
                ?? (gifProps?[kCGImagePropertyGIFDelayTime as String] as? Double)
                ?? 0.1
            totalDuration += max(0.02, delay)
        }

        imageView.animationImages = images
        imageView.animationDuration = max(0.2, totalDuration)
        imageView.startAnimating()
    }
}
