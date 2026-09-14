import CoreAudio
import CoreGraphics

@MainActor
protocol SystemAudioCapturing: AnyObject {
    func start(levels: @escaping @Sendable ([CGFloat]) -> Void,
               failure: @escaping @Sendable () -> Void) async throws
    func stop() async
}

enum SystemAudioCaptureError: Error, Equatable {
    case permissionDenied
    case coreAudio(operation: String, status: OSStatus)
    case unsupportedFormat
}
