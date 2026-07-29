import AVFoundation
import PhotosUI
import SwiftUI

/// Сканирование QR камерой.
struct QrScannerView: UIViewControllerRepresentable {

    let onResult: (String?) -> Void

    func makeUIViewController(context: Context) -> ScannerController {
        let controller = ScannerController()
        controller.onResult = onResult
        return controller
    }

    func updateUIViewController(_ controller: ScannerController, context: Context) {}

    final class ScannerController: UIViewController, AVCaptureMetadataOutputObjectsDelegate {

        var onResult: ((String?) -> Void)?

        private let session = AVCaptureSession()
        private var preview: AVCaptureVideoPreviewLayer?
        private var finished = false

        override func viewDidLoad() {
            super.viewDidLoad()
            view.backgroundColor = .black
            configureSession()
            addCloseButton()
        }

        override func viewDidLayoutSubviews() {
            super.viewDidLayoutSubviews()
            preview?.frame = view.bounds
        }

        override func viewWillAppear(_ animated: Bool) {
            super.viewWillAppear(animated)
            guard !session.isRunning else { return }
            DispatchQueue.global(qos: .userInitiated).async { [session] in
                session.startRunning()
            }
        }

        override func viewWillDisappear(_ animated: Bool) {
            super.viewWillDisappear(animated)
            if session.isRunning { session.stopRunning() }
        }

        private func configureSession() {
            guard let device = AVCaptureDevice.default(for: .video),
                  let input = try? AVCaptureDeviceInput(device: device),
                  session.canAddInput(input) else {
                showError("Камера недоступна")
                return
            }
            session.addInput(input)

            let output = AVCaptureMetadataOutput()
            guard session.canAddOutput(output) else {
                showError("Камера недоступна")
                return
            }
            session.addOutput(output)
            output.setMetadataObjectsDelegate(self, queue: .main)
            output.metadataObjectTypes = [.qr]

            let layer = AVCaptureVideoPreviewLayer(session: session)
            layer.videoGravity = .resizeAspectFill
            layer.frame = view.bounds
            view.layer.addSublayer(layer)
            preview = layer
        }

        private func addCloseButton() {
            let button = UIButton(type: .system)
            button.setTitle("Закрыть", for: .normal)
            button.setTitleColor(.white, for: .normal)
            button.addAction(UIAction { [weak self] _ in self?.finish(nil) }, for: .touchUpInside)
            button.translatesAutoresizingMaskIntoConstraints = false
            view.addSubview(button)
            NSLayoutConstraint.activate([
                button.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: 16),
                button.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 20),
            ])
        }

        private func showError(_ message: String) {
            let label = UILabel()
            label.text = message
            label.textColor = .white
            label.textAlignment = .center
            label.frame = view.bounds
            view.addSubview(label)
        }

        func metadataOutput(
            _ output: AVCaptureMetadataOutput,
            didOutput metadataObjects: [AVMetadataObject],
            from connection: AVCaptureConnection
        ) {
            guard let object = metadataObjects.first as? AVMetadataMachineReadableCodeObject,
                  let value = object.stringValue else { return }
            finish(value)
        }

        private func finish(_ value: String?) {
            guard !finished else { return }
            finished = true
            if session.isRunning { session.stopRunning() }
            onResult?(value)
        }
    }
}

/// Выбор картинки с QR-кодом из галереи.
struct QrImagePicker: UIViewControllerRepresentable {

    let onResult: (String?) -> Void

    func makeUIViewController(context: Context) -> PHPickerViewController {
        var configuration = PHPickerConfiguration()
        configuration.filter = .images
        configuration.selectionLimit = 1
        let controller = PHPickerViewController(configuration: configuration)
        controller.delegate = context.coordinator
        return controller
    }

    func updateUIViewController(_ controller: PHPickerViewController, context: Context) {}

    func makeCoordinator() -> Coordinator { Coordinator(onResult: onResult) }

    final class Coordinator: NSObject, PHPickerViewControllerDelegate {
        private let onResult: (String?) -> Void

        init(onResult: @escaping (String?) -> Void) {
            self.onResult = onResult
        }

        func picker(_ picker: PHPickerViewController, didFinishPicking results: [PHPickerResult]) {
            guard let provider = results.first?.itemProvider,
                  provider.canLoadObject(ofClass: UIImage.self) else {
                onResult(nil)
                return
            }
            provider.loadObject(ofClass: UIImage.self) { [onResult] object, _ in
                let decoded = (object as? UIImage).flatMap(QrUtils.decode)
                DispatchQueue.main.async { onResult(decoded) }
            }
        }
    }
}
