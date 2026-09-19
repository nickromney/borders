@preconcurrency import AVFoundation
import BordersCore
import Foundation

struct BrightnessCameraDevice: Identifiable, Equatable {
    let id: String
    let name: String
}

/// AVFoundation adapter for the optional camera feedback loop. It never saves
/// frames or creates a preview; it samples a small central region only.
final class WebcamLuminanceSampler: NSObject, AVCaptureVideoDataOutputSampleBufferDelegate {
    var onLuminance: ((Double) -> Void)?
    var onStatus: ((String) -> Void)?

    private let session = AVCaptureSession()
    private let sessionQueue = DispatchQueue(label: "com.nickromney.Borders.luminance.session")
    private let sessionQueueKey = DispatchSpecificKey<Void>()
    private let frameQueue = DispatchQueue(label: "com.nickromney.Borders.luminance.frames")
    private var videoOutput: AVCaptureVideoDataOutput?
    private var currentDevice: AVCaptureDevice?
    private var currentDeviceID: String?
    private var exposureDevice: AVCaptureDevice?
    private var exposureModeBeforeLock: AVCaptureDevice.ExposureMode?
    private var sampleInterval = 0.5
    private var locksCameraExposure = true
    private var lastSampleAt: Date?
    private var firstFrameFormat: OSType?
    private let deliversCallbacksOnMain: Bool

    init(deliversCallbacksOnMain: Bool = true) {
        self.deliversCallbacksOnMain = deliversCallbacksOnMain
        super.init()
        sessionQueue.setSpecific(key: sessionQueueKey, value: ())
    }

    func availableDevices() -> [BrightnessCameraDevice] {
        let devices = availableAVDevices()
        let candidates = devices.map {
            BrightnessCameraCandidate(
                id: $0.uniqueID,
                name: $0.localizedName,
                isExternal: isExternal($0)
            )
        }
        let preferred = BrightnessCameraSelectionPolicy.sortedByPreference(candidates)
        return preferred.compactMap { candidate in
            devices.first { $0.uniqueID == candidate.id }
                .map { BrightnessCameraDevice(id: $0.uniqueID, name: $0.localizedName) }
        }
    }

    func start(deviceID: String,
               sampleInterval: TimeInterval,
               locksCameraExposure: Bool) {
        self.sampleInterval = max(0.1, sampleInterval)
        self.locksCameraExposure = locksCameraExposure
        report("Requesting Camera access…")
        AVCaptureDevice.requestAccess(for: .video) { [weak self] granted in
            guard let self else { return }
            guard granted else {
                self.report("Camera access was denied")
                return
            }
            self.sessionQueue.async {
                self.configureAndStart(deviceID: deviceID)
            }
        }
    }

    func stop() {
        sessionQueue.async { [weak self] in
            self?.stopSession()
        }
    }

    /// Stops the capture session and restores camera configuration before returning.
    /// This is used by the command-line hardware test so light-state restoration
    /// cannot race the camera teardown when the process exits.
    func stopAndWait() {
        if DispatchQueue.getSpecific(key: sessionQueueKey) != nil {
            stopSession()
        } else {
            sessionQueue.sync { [weak self] in
                self?.stopSession()
            }
        }
    }

    private func configureAndStart(deviceID: String) {
        stopSession()
        guard let device = availableAVDevices().first(where: { $0.uniqueID == deviceID }) else {
            report("The selected camera is no longer available")
            return
        }

        do {
            try configureSession(with: device)
            currentDevice = device
            currentDeviceID = device.uniqueID
            lastSampleAt = nil
            firstFrameFormat = nil
            session.startRunning()
            try applyPreferredCaptureFormat(for: device)
            report("Monitoring \(device.localizedName)")
            scheduleExposureLock(for: device)
        } catch {
            report(error.localizedDescription)
        }
    }

    private func availableAVDevices() -> [AVCaptureDevice] {
        AVCaptureDevice.DiscoverySession(
            deviceTypes: [.external, .builtInWideAngleCamera],
            mediaType: .video,
            position: .unspecified
        ).devices
    }

    private func isExternal(_ device: AVCaptureDevice) -> Bool {
        device.deviceType == .external
    }

    private func configureSession(with device: AVCaptureDevice) throws {
        session.beginConfiguration()
        defer { session.commitConfiguration() }
        clearSession()
        applyPreferredSessionPreset()

        let input = try AVCaptureDeviceInput(device: device)
        guard session.canAddInput(input) else { throw SamplerError.cannotAddInput }
        session.addInput(input)

        let output = AVCaptureVideoDataOutput()
        output.alwaysDiscardsLateVideoFrames = true
        output.videoSettings = [
            kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA
        ]
        guard session.canAddOutput(output) else { throw SamplerError.cannotAddOutput }
        session.addOutput(output)
        try applyPreferredCaptureFormat(for: device)
        output.setSampleBufferDelegate(self, queue: frameQueue)
        videoOutput = output
    }

    private func applyPreferredSessionPreset() {
        for preset in [AVCaptureSession.Preset.photo,
                       .hd4K3840x2160,
                       .hd1920x1080,
                       .high] where session.canSetSessionPreset(preset) {
            session.sessionPreset = preset
            return
        }
    }

    private func applyPreferredCaptureFormat(for device: AVCaptureDevice) throws {
        let candidates = device.formats.map { format in
            let dimensions = CMVideoFormatDescriptionGetDimensions(format.formatDescription)
            let maxFrameRate = format.videoSupportedFrameRateRanges
                .map(\.maxFrameRate)
                .max() ?? 0
            return CameraCaptureFormatCandidate(
                width: Int(dimensions.width),
                height: Int(dimensions.height),
                maxFrameRate: maxFrameRate,
                pixelFormatScore: pixelFormatScore(for: format)
            )
        }
        guard let preferredIndex = CameraCaptureFormatPolicy.preferredIndex(in: candidates) else { return }

        let format = device.formats[preferredIndex]
        let frameRateRange = format.videoSupportedFrameRateRanges.max { lhs, rhs in
            lhs.maxFrameRate < rhs.maxFrameRate
        }
        try device.lockForConfiguration()
        defer { device.unlockForConfiguration() }
        device.activeFormat = format
        if let frameRateRange {
            device.activeVideoMinFrameDuration = frameRateRange.minFrameDuration
            device.activeVideoMaxFrameDuration = frameRateRange.minFrameDuration
        }
    }

    private func pixelFormatScore(for format: AVCaptureDevice.Format) -> Int {
        switch CMFormatDescriptionGetMediaSubType(format.formatDescription) {
        case kCVPixelFormatType_420YpCbCr8BiPlanarVideoRange:
            return 3
        case kCVPixelFormatType_420YpCbCr8BiPlanarFullRange:
            return 2
        case kCVPixelFormatType_422YpCbCr8:
            return 1
        default:
            return 0
        }
    }

    private func stopSession() {
        session.stopRunning()
        restoreExposureIfNeeded()
        session.beginConfiguration()
        clearSession()
        session.commitConfiguration()
        currentDevice = nil
        currentDeviceID = nil
        lastSampleAt = nil
    }

    private func clearSession() {
        if let videoOutput {
            videoOutput.setSampleBufferDelegate(nil, queue: nil)
            session.removeOutput(videoOutput)
        }
        session.inputs.forEach(session.removeInput)
        videoOutput = nil
    }

    private func scheduleExposureLock(for device: AVCaptureDevice) {
        guard locksCameraExposure else { return }
        sessionQueue.asyncAfter(deadline: .now() + 1) { [weak self, weak device] in
            guard let self, let device,
                  self.currentDeviceID == device.uniqueID,
                  self.session.isRunning else { return }
            self.lockExposure(on: device)
        }
    }

    private func lockExposure(on device: AVCaptureDevice) {
        guard device.isExposureModeSupported(.locked) else {
            report("Monitoring \(device.localizedName) (auto exposure)")
            return
        }

        do {
            try device.lockForConfiguration()
            exposureDevice = device
            exposureModeBeforeLock = device.exposureMode
            device.exposureMode = .locked
            device.unlockForConfiguration()
            report("Monitoring \(device.localizedName) (exposure locked)")
        } catch {
            report("Monitoring \(device.localizedName) (auto exposure)")
        }
    }

    private func restoreExposureIfNeeded() {
        guard let device = exposureDevice,
              let mode = exposureModeBeforeLock else { return }
        defer {
            exposureDevice = nil
            exposureModeBeforeLock = nil
        }
        guard device.isExposureModeSupported(mode) else { return }
        guard (try? device.lockForConfiguration()) != nil else { return }
        defer { device.unlockForConfiguration() }
        device.exposureMode = mode
    }

    private func report(_ message: String) {
        let handler = onStatus
        deliver {
            handler?(message)
        }
    }

    private func deliver(_ callback: @escaping () -> Void) {
        if deliversCallbacksOnMain {
            DispatchQueue.main.async(execute: callback)
        } else {
            callback()
        }
    }

    private func shouldSample(at date: Date) -> Bool {
        guard let lastSampleAt else { return true }
        return date.timeIntervalSince(lastSampleAt) >= sampleInterval
    }

    private func luminance(in pixelBuffer: CVPixelBuffer) -> Double? {
        let pixelFormat = CVPixelBufferGetPixelFormatType(pixelBuffer)
        let isBGRA = pixelFormat == kCVPixelFormatType_32BGRA
        let isVideoRangeLuma = pixelFormat == kCVPixelFormatType_420YpCbCr8BiPlanarVideoRange
        let isFullRangeLuma = pixelFormat == kCVPixelFormatType_420YpCbCr8BiPlanarFullRange
        guard isBGRA || isVideoRangeLuma || isFullRangeLuma else { return nil }

        CVPixelBufferLockBaseAddress(pixelBuffer, .readOnly)
        defer { CVPixelBufferUnlockBaseAddress(pixelBuffer, .readOnly) }

        let width = CVPixelBufferGetWidth(pixelBuffer)
        let height = CVPixelBufferGetHeight(pixelBuffer)
        let xStart = width / 5
        let xEnd = width - xStart
        let yStart = height / 5
        let yEnd = height - yStart
        let xStride = max(1, width / 64)
        let yStride = max(1, height / 64)

        if isBGRA {
            return bgraLuminance(
                pixelBuffer,
                xStart: xStart,
                xEnd: xEnd,
                yStart: yStart,
                yEnd: yEnd,
                xStride: xStride,
                yStride: yStride
            )
        }
        return lumaPlaneLuminance(
            pixelBuffer,
            fullRange: isFullRangeLuma,
            xStart: xStart,
            xEnd: xEnd,
            yStart: yStart,
            yEnd: yEnd,
            xStride: xStride,
            yStride: yStride
        )
    }

    private func bgraLuminance(_ pixelBuffer: CVPixelBuffer,
                               xStart: Int,
                               xEnd: Int,
                               yStart: Int,
                               yEnd: Int,
                               xStride: Int,
                               yStride: Int) -> Double? {
        guard let baseAddress = CVPixelBufferGetBaseAddress(pixelBuffer) else { return nil }
        let bytes = baseAddress.assumingMemoryBound(to: UInt8.self)
        let bytesPerRow = CVPixelBufferGetBytesPerRow(pixelBuffer)
        return meanRegion(xStart: xStart, xEnd: xEnd, yStart: yStart, yEnd: yEnd,
                          xStride: xStride, yStride: yStride) { x, y in
            let pixel = bytes + (y * bytesPerRow) + (x * 4)
            return (0.2126 * Double(pixel[2]) +
                    0.7152 * Double(pixel[1]) +
                    0.0722 * Double(pixel[0])) / 255
        }
    }

    private func lumaPlaneLuminance(_ pixelBuffer: CVPixelBuffer,
                                    fullRange: Bool,
                                    xStart: Int,
                                    xEnd: Int,
                                    yStart: Int,
                                    yEnd: Int,
                                    xStride: Int,
                                    yStride: Int) -> Double? {
        guard let baseAddress = CVPixelBufferGetBaseAddressOfPlane(pixelBuffer, 0) else { return nil }
        let bytes = baseAddress.assumingMemoryBound(to: UInt8.self)
        let bytesPerRow = CVPixelBufferGetBytesPerRowOfPlane(pixelBuffer, 0)
        return meanRegion(xStart: xStart, xEnd: xEnd, yStart: yStart, yEnd: yEnd,
                          xStride: xStride, yStride: yStride) { x, y in
            let value = Double(bytes[(y * bytesPerRow) + x])
            return fullRange
                ? LuminanceMeasurement.normalizedFullRangeLuma(value)
                : LuminanceMeasurement.normalizedVideoRangeLuma(value)
        }
    }

    private func meanRegion(xStart: Int,
                            xEnd: Int,
                            yStart: Int,
                            yEnd: Int,
                            xStride: Int,
                            yStride: Int,
                            valueAt: (Int, Int) -> Double) -> Double? {
        var total = 0.0
        var count = 0
        for y in stride(from: yStart, to: yEnd, by: yStride) {
            for x in stride(from: xStart, to: xEnd, by: xStride) {
                total += valueAt(x, y)
                count += 1
            }
        }
        guard count > 0 else { return nil }
        return total / Double(count)
    }

    func captureOutput(_ output: AVCaptureOutput,
                       didOutput sampleBuffer: CMSampleBuffer,
                       from connection: AVCaptureConnection) {
        let pixelFormat = CMSampleBufferGetImageBuffer(sampleBuffer)
            .map(CVPixelBufferGetPixelFormatType)
        if firstFrameFormat == nil, let pixelFormat {
            firstFrameFormat = pixelFormat
            report("Monitoring camera frames (\(pixelFormatName(pixelFormat)))")
        }
        let now = Date()
        guard shouldSample(at: now),
              let pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer),
              let value = luminance(in: pixelBuffer) else { return }
        lastSampleAt = now
        let handler = onLuminance
        deliver {
            handler?(value)
        }
    }

    private func pixelFormatName(_ pixelFormat: OSType) -> String {
        switch pixelFormat {
        case kCVPixelFormatType_32BGRA:
            return "BGRA"
        case kCVPixelFormatType_420YpCbCr8BiPlanarVideoRange:
            return "420v"
        case kCVPixelFormatType_420YpCbCr8BiPlanarFullRange:
            return "420f"
        case kCVPixelFormatType_422YpCbCr8:
            return "yuvs"
        default:
            return String(format: "0x%08X", pixelFormat)
        }
    }
}

private enum SamplerError: LocalizedError {
    case cannotAddInput
    case cannotAddOutput

    var errorDescription: String? {
        switch self {
        case .cannotAddInput:
            "The selected camera cannot be opened"
        case .cannotAddOutput:
            "The camera output could not be configured"
        }
    }
}
