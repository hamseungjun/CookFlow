import SwiftUI
import AVFoundation
import CoreImage
import UIKit

final class LiveCamera: NSObject, ObservableObject, AVCaptureVideoDataOutputSampleBufferDelegate {
    let session = AVCaptureSession()
    @Published var error: String?
    private let queue = DispatchQueue(label: "cookflow.live.camera")
    private let context = CIContext()
    private var lastFrame: TimeInterval = 0
    private var configured = false
    var onFrame: ((Data) -> Void)?
    // Generated inputs are available only in an explicitly isolated DEBUG demo.
    var demoIngredientID: String?
    @Published var demoImage: UIImage?
    private var demoTimer: Timer?
    static var generatedDemo: Bool {
        #if DEBUG
        return ProcessInfo.processInfo.arguments.contains("--ui-test") && ProcessInfo.processInfo.arguments.contains("--demo-generated-inputs")
        #else
        return false
        #endif
    }
    private func emitDemoFrame() {
        guard let id = demoIngredientID,
              let root = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first,
              let bytes = try? Data(contentsOf: root.appendingPathComponent("DemoInputs/" + id + ".jpg")),
              let image = UIImage(data: bytes) else { return }
        demoImage = image
        onFrame?(bytes)
    }
    func start() {
        if Self.generatedDemo {
            demoTimer?.invalidate()
            emitDemoFrame()
            demoTimer = Timer.scheduledTimer(withTimeInterval: 3, repeats: true) { [weak self] _ in self?.emitDemoFrame() }
            return
        }
        queue.async { [weak self] in
            guard let self else { return }
            do {
                if !self.configured {
                    self.session.beginConfiguration()
                    self.session.sessionPreset = .medium
                    guard let device = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .back) else { self.session.commitConfiguration(); throw RecipeError.invalid("이 기기에서는 카메라를 사용할 수 없어요. 직접 확인으로 진행해주세요.") }
                    let input = try AVCaptureDeviceInput(device: device)
                    guard self.session.canAddInput(input) else { self.session.commitConfiguration(); throw RecipeError.invalid("카메라를 열지 못했습니다.") }
                    self.session.addInput(input)
                    let output = AVCaptureVideoDataOutput(); output.alwaysDiscardsLateVideoFrames = true
                    output.setSampleBufferDelegate(self, queue: self.queue)
                    guard self.session.canAddOutput(output) else { self.session.commitConfiguration(); throw RecipeError.invalid("카메라 화면을 읽지 못했습니다.") }
                    self.session.addOutput(output)
                    if let connection = output.connection(with: .video), connection.isVideoRotationAngleSupported(90) { connection.videoRotationAngle = 90 }
                    self.session.commitConfiguration(); self.configured = true
                }
                if !self.session.isRunning { self.session.startRunning() }
            } catch { DispatchQueue.main.async { self.error = error.localizedDescription } }
        }
    }
    func stop() { demoTimer?.invalidate(); demoTimer = nil; queue.async { [weak self] in if self?.session.isRunning == true { self?.session.stopRunning() } } }
    func captureOutput(_ output: AVCaptureOutput, didOutput sampleBuffer: CMSampleBuffer, from connection: AVCaptureConnection) {
        let now = ProcessInfo.processInfo.systemUptime
        guard now - lastFrame >= 3, let pixel = CMSampleBufferGetImageBuffer(sampleBuffer) else { return }
        lastFrame = now
        let input = CIImage(cvPixelBuffer: pixel)
        let scale = min(1, 1000 / max(input.extent.width, input.extent.height))
        let resized = input.transformed(by: CGAffineTransform(scaleX: scale, y: scale))
        guard let cg = context.createCGImage(resized, from: resized.extent), let data = UIImage(cgImage: cg).jpegData(compressionQuality: 0.7) else { return }
        DispatchQueue.main.async { [weak self] in self?.onFrame?(data) }
    }
}
private final class CameraSurface: UIView {
    override class var layerClass: AnyClass { AVCaptureVideoPreviewLayer.self }
    var preview: AVCaptureVideoPreviewLayer { layer as! AVCaptureVideoPreviewLayer }
}
struct LiveCameraPreview: UIViewRepresentable {
    let camera: LiveCamera
    func makeUIView(context: Context) -> UIView { let view = CameraSurface(); view.preview.session = camera.session; view.preview.videoGravity = .resizeAspectFill; return view }
    func updateUIView(_ view: UIView, context: Context) {
        guard let surface = view as? CameraSurface, let connection = surface.preview.connection else { return }
        let orientation = view.window?.windowScene?.interfaceOrientation ?? .portrait
        let angle: CGFloat = orientation == .landscapeLeft ? 0 : orientation == .landscapeRight ? 180 : orientation == .portraitUpsideDown ? 270 : 90
        if connection.isVideoRotationAngleSupported(angle) { connection.videoRotationAngle = angle }
    }
}
