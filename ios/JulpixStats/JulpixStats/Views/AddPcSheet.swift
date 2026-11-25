import AVFoundation
import SwiftUI

struct AddPcSheet: View {
    @EnvironmentObject var connectionManager: PcConnectionManager
    @Environment(\.dismiss) var dismiss

    @State private var name = ""
    @State private var ip = ""
    @State private var port = "52840"
    @State private var pin = ""
    @State private var showScanner = false
    @State private var statusMsg: String?

    var body: some View {
        NavigationStack {
            HStack(spacing: 16) {
                // Left: Saved PCs & Discovery
                VStack(alignment: .leading, spacing: 12) {
                    Text("Gespeicherte PCs")
                        .font(.headline)

                    if connectionManager.savedPcs.isEmpty {
                        Text("Noch kein PC hinzugefügt.")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    } else {
                        List {
                            ForEach(connectionManager.savedPcs) { pc in
                                HStack {
                                    VStack(alignment: .leading) {
                                        Text(pc.name).font(.subheadline.bold())
                                        Text("\(pc.ip):\(pc.port)")
                                            .font(.caption)
                                            .foregroundColor(.secondary)
                                    }
                                    Spacer()
                                    if connectionManager.activePcId == pc.id {
                                        Image(systemName: "checkmark.circle.fill")
                                            .foregroundColor(.green)
                                    }
                                }
                                .contentShape(Rectangle())
                                .onTapGesture {
                                    connectionManager.selectPc(pc)
                                    dismiss()
                                }
                            }
                            .onDelete { offsets in
                                for idx in offsets {
                                    connectionManager.removePc(connectionManager.savedPcs[idx])
                                }
                            }
                        }
                        .listStyle(.plain)
                        .frame(maxHeight: 150)
                    }

                    Divider()

                    HStack {
                        Text("Im WLAN gefunden")
                            .font(.headline)
                        Spacer()
                        Button {
                            connectionManager.discoverLocalPcs()
                        } label: {
                            if connectionManager.isDiscovering {
                                ProgressView()
                            } else {
                                Label("Suchen", systemImage: "antenna.radiowaves.left.and.right")
                                    .font(.caption.bold())
                            }
                        }
                        .buttonStyle(.bordered)
                    }

                    ScrollView {
                        VStack(spacing: 8) {
                            ForEach(connectionManager.discoveredPcs) { found in
                                Button {
                                    name = found.name
                                    ip = found.ip
                                    port = "\(found.port)"
                                } label: {
                                    HStack {
                                        Image(systemName: "desktopcomputer")
                                        VStack(alignment: .leading) {
                                            Text(found.name).font(.subheadline.bold())
                                            Text("\(found.ip):\(found.port)").font(.caption).foregroundColor(.secondary)
                                        }
                                        Spacer()
                                        Text("Übernehmen").font(.caption).foregroundColor(.cyan)
                                    }
                                    .padding(10)
                                    .background(Color.white.opacity(0.08))
                                    .cornerRadius(10)
                                }
                                .buttonStyle(.plain)
                            }
                        }
                    }
                }
                .frame(maxWidth: .infinity)

                Divider()

                // Right: QR Scanner + Manual Form
                VStack(alignment: .leading, spacing: 12) {
                    Button {
                        showScanner = true
                    } label: {
                        Label("QR-Code von JulpixConnect scannen", systemImage: "qrcode.viewfinder")
                            .font(.subheadline.bold())
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 10)
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(.cyan)

                    Text("Oder manuell eingeben:")
                        .font(.caption)
                        .foregroundColor(.secondary)

                    TextField("PC-Name (z.B. Gaming-PC)", text: $name)
                        .textFieldStyle(.roundedBorder)

                    HStack {
                        TextField("IP-Adresse (z.B. 192.168.1.42)", text: $ip)
                            .textFieldStyle(.roundedBorder)
                            .keyboardType(.decimalPad)
                        TextField("Port", text: $port)
                            .textFieldStyle(.roundedBorder)
                            .keyboardType(.numberPad)
                            .frame(width: 85)
                    }

                    TextField("6-stelliger Pairing-PIN", text: $pin)
                        .textFieldStyle(.roundedBorder)
                        .keyboardType(.numberPad)

                    if let statusMsg {
                        Text(statusMsg)
                            .font(.caption)
                            .foregroundColor(.orange)
                    }

                    Spacer()

                    Button {
                        saveManualPc()
                    } label: {
                        Text("PC hinzufügen & verbinden")
                            .font(.subheadline.bold())
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 10)
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(.green)
                    .disabled(ip.trimmingCharacters(in: .whitespaces).isEmpty || pin.trimmingCharacters(in: .whitespaces).isEmpty)
                }
                .frame(maxWidth: .infinity)
            }
            .padding()
            .navigationTitle("PC hinzufügen")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Fertig") { dismiss() }
                }
            }
            .fullScreenCover(isPresented: $showScanner) {
                QrScannerSheet { code in
                    showScanner = false
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) {
                        handleQrCode(code)
                    }
                }
            }
            .onAppear {
                connectionManager.discoverLocalPcs()
            }
        }
    }

    private func saveManualPc() {
        let cleanIp = ip.trimmingCharacters(in: .whitespacesAndNewlines)
        let cleanPin = pin.trimmingCharacters(in: .whitespacesAndNewlines)
        let cleanName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        let portNum = Int(port) ?? 52840

        let pc = SavedPc(
            name: cleanName.isEmpty ? cleanIp : cleanName,
            ip: cleanIp,
            port: portNum,
            pin: cleanPin
        )
        connectionManager.addOrUpdatePc(pc)
        dismiss()
    }

    private func handleQrCode(_ raw: String) {
        guard let data = raw.data(using: .utf8),
              let payload = try? JSONDecoder().decode(QrPairingPayload.self, from: data) else {
            statusMsg = "QR-Code nicht erkannt (kein JulpixConnect-Code)."
            return
        }
        let pc = SavedPc(name: payload.name, ip: payload.ip, port: payload.port, pin: payload.pin)
        connectionManager.addOrUpdatePc(pc)
        dismiss()
    }
}

// MARK: - AVFoundation QR Code Scanner

struct QrScannerSheet: View {
    @Environment(\.dismiss) var dismiss
    let onScanned: (String) -> Void

    var body: some View {
        ZStack(alignment: .topTrailing) {
            QrCameraPreview(onScanned: onScanned)
                .ignoresSafeArea()

            Button {
                dismiss()
            } label: {
                Image(systemName: "xmark.circle.fill")
                    .font(.title)
                    .foregroundColor(.white)
                    .padding()
            }
        }
    }
}

struct QrCameraPreview: UIViewControllerRepresentable {
    let onScanned: (String) -> Void

    func makeUIViewController(context: Context) -> QrScannerViewController {
        let vc = QrScannerViewController()
        vc.onScanned = onScanned
        return vc
    }

    func updateUIViewController(_ uiViewController: QrScannerViewController, context: Context) {}
}

final class QrScannerViewController: UIViewController, AVCaptureMetadataOutputObjectsDelegate {
    var onScanned: ((String) -> Void)?
    private let session = AVCaptureSession()
    private let sessionQueue = DispatchQueue(label: "com.julpix.qr.session")
    private var previewLayer: AVCaptureVideoPreviewLayer?
    private var didScan = false

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .black

        let preview = AVCaptureVideoPreviewLayer(session: session)
        preview.videoGravity = .resizeAspectFill
        preview.frame = view.bounds
        view.layer.addSublayer(preview)
        self.previewLayer = preview

        let status = AVCaptureDevice.authorizationStatus(for: .video)
        switch status {
        case .authorized:
            configureAndStartSession()
        case .notDetermined:
            AVCaptureDevice.requestAccess(for: .video) { [weak self] granted in
                if granted {
                    self?.configureAndStartSession()
                } else {
                    DispatchQueue.main.async {
                        self?.showCameraError("Kamerazugriff verweigert. Bitte in den iPhone-Einstellungen aktivieren.")
                    }
                }
            }
        case .denied, .restricted:
            showCameraError("Kamerazugriff verweigert. Bitte in den iPhone-Einstellungen für JulpixStats aktivieren.")
        @unknown default:
            showCameraError("Kamera nicht verfügbar.")
        }
    }

    private func configureAndStartSession() {
        sessionQueue.async { [weak self] in
            guard let self else { return }
            self.session.beginConfiguration()

            guard let device = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .back)
                    ?? AVCaptureDevice.default(for: .video),
                  let input = try? AVCaptureDeviceInput(device: device),
                  self.session.canAddInput(input) else {
                self.session.commitConfiguration()
                DispatchQueue.main.async {
                    self.showCameraError("Kamera konnte nicht gestartet werden.")
                }
                return
            }

            self.session.addInput(input)

            let output = AVCaptureMetadataOutput()
            if self.session.canAddOutput(output) {
                self.session.addOutput(output)
                output.setMetadataObjectsDelegate(self, queue: DispatchQueue.main)
                if output.availableMetadataObjectTypes.contains(.qr) {
                    output.metadataObjectTypes = [.qr]
                }
            }

            self.session.commitConfiguration()
            self.session.startRunning()

            DispatchQueue.main.async {
                self.updatePreviewOrientation()
            }
        }
    }

    private func showCameraError(_ text: String) {
        let label = UILabel()
        label.text = text
        label.textColor = .white
        label.textAlignment = .center
        label.numberOfLines = 0
        label.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(label)
        NSLayoutConstraint.activate([
            label.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            label.centerYAnchor.constraint(equalTo: view.centerYAnchor),
            label.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 24),
            label.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -24)
        ])
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        previewLayer?.frame = view.bounds
        updatePreviewOrientation()
    }

    private func updatePreviewOrientation() {
        if let conn = previewLayer?.connection, conn.isVideoOrientationSupported {
            let interfaceOrientation = view.window?.windowScene?.interfaceOrientation
            switch interfaceOrientation {
            case .landscapeLeft: conn.videoOrientation = .landscapeLeft
            case .landscapeRight: conn.videoOrientation = .landscapeRight
            default: conn.videoOrientation = .landscapeRight
            }
        }
    }

    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        sessionQueue.async { [weak self] in
            if self?.session.isRunning == true {
                self?.session.stopRunning()
            }
        }
    }

    func metadataOutput(_ output: AVCaptureMetadataOutput, didOutput metadataObjects: [AVMetadataObject], from connection: AVCaptureConnection) {
        guard !didScan,
              let obj = metadataObjects.first as? AVMetadataMachineReadableCodeObject,
              let str = obj.stringValue else { return }
        didScan = true
        sessionQueue.async { [weak self] in
            if self?.session.isRunning == true {
                self?.session.stopRunning()
            }
        }
        onScanned?(str)
    }
}
