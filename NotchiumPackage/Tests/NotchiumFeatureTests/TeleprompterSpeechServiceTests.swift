import AVFoundation
import AppKit
import CoreMedia
import XCTest
@testable import NotchiumServices

@MainActor
final class TeleprompterSpeechServiceTests: XCTestCase {
    func testAudioQueuesKeepTwoSecondsOfBoundedSchedulingHeadroom() {
        for rate in [24_000.0, 48_000.0, 96_000.0] {
            let packets = TeleprompterAudioBuffering.packetCapacity(sampleRate: rate)
            let seconds = Double(packets * 1024) / rate
            XCTAssertGreaterThanOrEqual(seconds, 2)
            XCTAssertLessThan(seconds, 2.05)
            XCTAssertLessThanOrEqual(packets, 256)
        }
        XCTAssertEqual(TeleprompterAudioBuffering.packetCapacity(sampleRate: .nan), 16)
        XCTAssertEqual(TeleprompterAudioBuffering.packetCapacity(sampleRate: .greatestFiniteMagnitude), 256)
    }

    func testRawMeterRateIsIndependentOfRecognitionConsumption() {
        let gate = TeleprompterAudioLevelGate(sampleRate: 48_000)
        // No converter/analyzer is consumed in this test: tap-side levels still report.
        let reports = (0..<47).filter { _ in gate.shouldReport(frameCount: 1024) }.count
        XCTAssertGreaterThanOrEqual(reports, 20)
        XCTAssertLessThanOrEqual(reports, 25)
        XCTAssertFalse(gate.shouldReport(frameCount: 0))
    }

    func testAirPodsRateMonoConversionPreservesAudibleSamples() async throws {
        let input = try XCTUnwrap(AVAudioFormat(commonFormat: .pcmFormatFloat32, sampleRate: 24_000,
                                              channels: 1, interleaved: false))
        let output = try XCTUnwrap(AVAudioFormat(commonFormat: .pcmFormatInt16, sampleRate: 16_000,
                                               channels: 1, interleaved: false))
        let converter = try XCTUnwrap(TeleprompterSpeechAudioConverter(inputFormat: input, outputFormat: output))
        let packet = TeleprompterMicrophonePacket(samples: [[Float](repeating: 0.15, count: 1024)],
            frameCount: 1024, sampleTime: 0, rms: 0.15)
        let result = try await converter.convert(packet)
        let converted = try XCTUnwrap(result)
        if #available(macOS 27, *) {
            let buffer = converted.buffer
            XCTAssertGreaterThan(buffer.frameLength, 0)
            let samples = try XCTUnwrap(buffer.int16ChannelData)
            let energy = (0..<Int(buffer.frameLength)).reduce(0.0) { sum, frame in
                let value = Double(samples[0][frame]) / Double(Int16.max)
                return sum + value * value
            }
            XCTAssertEqual(sqrt(energy / Double(buffer.frameLength)), 0.15, accuracy: 0.03)
        }
    }

    func testSelectedMicrophoneUIDReachesProviderWithoutChangingDefaultChoice() async throws {
        let choices = [TeleprompterMicrophone(id: "builtin", name: "Built-in Microphone", isDefault: false),
                       TeleprompterMicrophone(id: "headset", name: "Headset", isDefault: true)]
        let service = MockTeleprompterSpeechService(microphones: choices)
        let actual = await service.inputDevices()
        XCTAssertEqual(actual, choices)
        _ = try await service.start(localeIdentifier: "en-US", inputDeviceID: "builtin")
        let selected = await service.requestedInputDeviceID
        XCTAssertEqual(selected, "builtin")
        await service.stop()
        _ = try await service.start(localeIdentifier: "en-US", inputDeviceID: nil)
        let systemDefault = await service.requestedInputDeviceID
        XCTAssertNil(systemDefault)
        await service.stop()
    }

    func testPublicLifecycleNotificationsMapToSuspensionAndAuthorizationRecheck() {
        for name in [NSWorkspace.willSleepNotification, NSWorkspace.screensDidSleepNotification,
                     NSWorkspace.sessionDidResignActiveNotification] {
            XCTAssertEqual(TeleprompterSpeechLifecycleObserver.event(for: name), .suspend)
        }
        XCTAssertEqual(TeleprompterSpeechLifecycleObserver.event(for: NSApplication.didBecomeActiveNotification), .becameActive)
        XCTAssertNil(TeleprompterSpeechLifecycleObserver.event(for: Notification.Name("unrelated")))
    }

    func testTapPacketOwnsItsSamplesAndSanitizesNonFiniteValues() throws {
        let format = try XCTUnwrap(AVAudioFormat(commonFormat: .pcmFormatFloat32, sampleRate: 16_000,
                                               channels: 1, interleaved: false))
        let buffer = try XCTUnwrap(AVAudioPCMBuffer(pcmFormat: format, frameCapacity: 4))
        buffer.frameLength = 4
        let samples = try XCTUnwrap(buffer.floatChannelData)
        samples[0][0] = 0.5
        samples[0][1] = -0.5
        samples[0][2] = .nan
        samples[0][3] = .infinity
        let packet = try XCTUnwrap(TeleprompterMicrophonePacket.copying(buffer, at: AVAudioTime(sampleTime: 123, atRate: 16_000)))
        samples[0][0] = 1
        XCTAssertEqual(packet.samples, [[0.5, -0.5, 0, 0]])
        XCTAssertEqual(packet.sampleTime, 123)
        XCTAssertEqual(packet.rms, sqrt(0.125), accuracy: 0.000_001)
    }

    func testInterleavedStereoIsCopiedByChannel() throws {
        let format = try XCTUnwrap(AVAudioFormat(commonFormat: .pcmFormatFloat32, sampleRate: 48_000,
                                               channels: 2, interleaved: true))
        let buffer = try XCTUnwrap(AVAudioPCMBuffer(pcmFormat: format, frameCapacity: 2))
        buffer.frameLength = 2
        let samples = try XCTUnwrap(buffer.floatChannelData)
        for (index, sample) in [Float(0.1), 0.2, 0.3, 0.4].enumerated() { samples[0][index] = sample }
        let packet = try XCTUnwrap(TeleprompterMicrophonePacket.copying(buffer, at: AVAudioTime(sampleTime: 0, atRate: 48_000)))
        XCTAssertEqual(packet.samples, [[0.1, 0.3], [0.2, 0.4]])
    }

    func testConverterAcceptsHardwareRateAndUsesContiguousAnalyzerTime() async throws {
        let hardware = try XCTUnwrap(AVAudioFormat(commonFormat: .pcmFormatFloat32, sampleRate: 48_000,
                                                 channels: 2, interleaved: false))
        let recognition = try XCTUnwrap(AVAudioFormat(commonFormat: .pcmFormatInt16, sampleRate: 16_000,
                                                    channels: 1, interleaved: false))
        let converter = try XCTUnwrap(TeleprompterSpeechAudioConverter(inputFormat: hardware, outputFormat: recognition))
        let packet = TeleprompterMicrophonePacket(samples: [[Float](repeating: 0.25, count: 960),
                                                            [Float](repeating: 0.25, count: 960)],
                                                  frameCount: 960, sampleTime: 0, rms: 0.25)
        let converted = try await converter.convert(packet)
        XCTAssertNotNil(converted)
        XCTAssertNil(converted?.bufferStartTime)
    }

    func testUnsupportedAnalyzerRepresentationIsRejectedBeforeNativeInitializer() throws {
        let floatingPoint = try XCTUnwrap(AVAudioFormat(commonFormat: .pcmFormatFloat32, sampleRate: 16_000,
                                                      channels: 1, interleaved: false))
        XCTAssertNil(TeleprompterSpeechAudioConverter(inputFormat: floatingPoint, outputFormat: floatingPoint))
    }

    func testFormatSelectionPrefersDeclaredSixteenKilohertzIntegerMono() throws {
        let floatingPoint = try XCTUnwrap(AVAudioFormat(commonFormat: .pcmFormatFloat32, sampleRate: 48_000,
                                                      channels: 1, interleaved: false))
        let standard = try XCTUnwrap(AVAudioFormat(commonFormat: .pcmFormatInt16, sampleRate: 16_000,
                                                 channels: 1, interleaved: false))
        let alternate = try XCTUnwrap(AVAudioFormat(commonFormat: .pcmFormatInt16, sampleRate: 24_000,
                                                  channels: 1, interleaved: false))
        let selected = TeleprompterSpeechAudioConverter.selectAnalyzerFormat(
            supported: [floatingPoint, alternate, standard], negotiated: floatingPoint)
        XCTAssertEqual(selected, standard)
    }

    func testFormatSelectionUsesCompatibleNegotiatedRateAndRejectsUnsupportedRepresentations() throws {
        let stereo = try XCTUnwrap(AVAudioFormat(commonFormat: .pcmFormatInt16, sampleRate: 16_000,
                                               channels: 2, interleaved: false))
        let floatingPoint = try XCTUnwrap(AVAudioFormat(commonFormat: .pcmFormatFloat32, sampleRate: 48_000,
                                                      channels: 1, interleaved: false))
        let lowRate = try XCTUnwrap(AVAudioFormat(commonFormat: .pcmFormatInt16, sampleRate: 24_000,
                                                channels: 1, interleaved: false))
        let highRate = try XCTUnwrap(AVAudioFormat(commonFormat: .pcmFormatInt16, sampleRate: 48_000,
                                                 channels: 1, interleaved: false))
        XCTAssertEqual(TeleprompterSpeechAudioConverter.selectAnalyzerFormat(
            supported: [lowRate, highRate, stereo, floatingPoint], negotiated: floatingPoint), highRate)
        XCTAssertNil(TeleprompterSpeechAudioConverter.selectAnalyzerFormat(
            supported: [stereo, floatingPoint], negotiated: floatingPoint))
        XCTAssertNil(TeleprompterSpeechAudioConverter.selectAnalyzerFormat(supported: [], negotiated: lowRate))
    }

    func testMockReplacementEndsOldStreamWithoutClosingNewStream() async throws {
        let service = MockTeleprompterSpeechService()
        let oldStream = try await service.start(localeIdentifier: "en-US")
        var old = oldStream.makeAsyncIterator()
        let initialOld = await old.next()
        XCTAssertEqual(initialOld, .ready)
        let newStream = try await service.start(localeIdentifier: "en-US")
        var current = newStream.makeAsyncIterator()
        let initialNew = await current.next()
        XCTAssertEqual(initialNew, .ready)
        let oldEnd = await old.next()
        XCTAssertNil(oldEnd)
        let event = TeleprompterSpeechEvent.transcript(text: "Hello", audioStart: 0, audioEnd: 0.5, isFinal: false)
        await service.emit(event)
        let received = await current.next()
        XCTAssertEqual(received, event)
        await service.stop()
        let newEnd = await current.next()
        XCTAssertNil(newEnd)
    }

    func testMockCanRepresentDeniedProviderWithoutOpeningMicrophone() async {
        let service = MockTeleprompterSpeechService(availability: .denied, failure: .microphoneDenied)
        let status = await service.availability(localeIdentifier: "en-US")
        XCTAssertEqual(status, .denied)
        do {
            _ = try await service.start(localeIdentifier: "en-US")
            XCTFail("Denied provider should fail")
        } catch {
            XCTAssertEqual(error as? TeleprompterSpeechFailure, .microphoneDenied)
        }
    }
}
