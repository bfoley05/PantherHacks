//
//  CameraManager.swift
//  PTApp
//

import AVFoundation
import Combine

@MainActor
final class CameraManager: NSObject, ObservableObject {
    let session = AVCaptureSession()

    @Published var isAuthorized = false
    @Published var flashOn = false
    @Published var cameraPosition: AVCaptureDevice.Position = .back

    private let sessionQueue = DispatchQueue(label: "stride.camera.session")

    func checkAuthorization() {
        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .authorized:
            isAuthorized = true
            configureSession(position: cameraPosition)
        case .notDetermined:
            AVCaptureDevice.requestAccess(for: .video) { [weak self] granted in
                Task { @MainActor in
                    guard let self else { return }
                    self.isAuthorized = granted
                    if granted { self.configureSession(position: self.cameraPosition) }
                }
            }
        default:
            isAuthorized = false
        }
    }

    func configureSession(position: AVCaptureDevice.Position) {
        sessionQueue.async { [weak self] in
            guard let self else { return }

            self.session.beginConfiguration()
            self.session.sessionPreset = .high

            self.session.inputs.forEach { self.session.removeInput($0) }

            guard let device = Self.camera(for: position),
                  let input = try? AVCaptureDeviceInput(device: device),
                  self.session.canAddInput(input)
            else {
                self.session.commitConfiguration()
                return
            }

            self.session.addInput(input)

            self.session.commitConfiguration()

            if !self.session.isRunning {
                self.session.startRunning()
            }
        }
    }

    func applyTorch() {
        let shouldOn = flashOn
        sessionQueue.async { [weak self] in
            guard let self else { return }
            guard let deviceInput = self.session.inputs.compactMap({ $0 as? AVCaptureDeviceInput }).first else { return }
            let device = deviceInput.device
            guard device.hasTorch else { return }
            do {
                try device.lockForConfiguration()
                if shouldOn, device.isTorchModeSupported(.on) {
                    try device.setTorchModeOn(level: 0.85)
                } else {
                    device.torchMode = .off
                }
                device.unlockForConfiguration()
            } catch {
                device.unlockForConfiguration()
            }
        }
    }

    func flipCamera() {
        cameraPosition = cameraPosition == .back ? .front : .back
        configureSession(position: cameraPosition)
    }

    func startRunningIfNeeded() {
        sessionQueue.async { [weak self] in
            guard let self else { return }
            if !self.session.isRunning {
                self.session.startRunning()
            }
        }
    }

    func stopRunning() {
        sessionQueue.async { [weak self] in
            guard let self else { return }
            if self.session.isRunning {
                self.session.stopRunning()
            }
        }
    }

    private static func camera(for position: AVCaptureDevice.Position) -> AVCaptureDevice? {
        AVCaptureDevice.DiscoverySession(
            deviceTypes: [.builtInWideAngleCamera],
            mediaType: .video,
            position: position
        ).devices.first
    }
}
