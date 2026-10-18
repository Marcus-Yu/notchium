import CoreAudio
import NotchiumRealtimeAudio
import XCTest

final class Stage27AudioBufferTests: XCTestCase {
    func testUnequalOutputBuffersRespectEachChannelsByteLimit() {
        for noninterleavedInput in [false, true] {
            for rightFrames in 0...8 {
                let input = AudioBufferList.allocate(maximumBuffers: 2)
                let output = AudioBufferList.allocate(maximumBuffers: 2)
                defer { free(input.unsafeMutablePointer); free(output.unsafeMutablePointer) }
                var source: [Float] = Array(repeating: 1, count: 8)
                var left: [Float] = Array(repeating: -99, count: 8)
                var right: [Float] = Array(repeating: -99, count: 8)
                var slot = NTAudioGainSlot()
                NTAudioGainSlotsInitialize(&slot, 1)
                NTAudioGainSlotSet(&slot, 0.5)

                source.withUnsafeMutableBytes { sourceBytes in
                    left.withUnsafeMutableBytes { leftBytes in
                        right.withUnsafeMutableBytes { rightBytes in
                            input.unsafeMutablePointer.pointee.mNumberBuffers = noninterleavedInput ? 2 : 1
                            input[0] = AudioBuffer(mNumberChannels: noninterleavedInput ? 1 : 2,
                                mDataByteSize: noninterleavedInput ? 16 : 32, mData: sourceBytes.baseAddress)
                            if noninterleavedInput {
                                input[1] = AudioBuffer(mNumberChannels: 1, mDataByteSize: 16,
                                    mData: sourceBytes.baseAddress!.advanced(by: 16))
                            }
                            output.unsafeMutablePointer.pointee.mNumberBuffers = 2
                            output[0] = AudioBuffer(mNumberChannels: 1, mDataByteSize: 16, mData: leftBytes.baseAddress)
                            output[1] = AudioBuffer(mNumberChannels: 1, mDataByteSize: UInt32(rightFrames * 4),
                                mData: rightBytes.baseAddress)
                            NTAudioMixFloat32(input.unsafePointer, output.unsafeMutablePointer, &slot, 1,
                                             noninterleavedInput, true)
                        }
                    }
                }
                XCTAssertEqual(Array(left.prefix(4)), Array(repeating: 0.5, count: 4))
                XCTAssertEqual(Array(left.suffix(4)), Array(repeating: -99, count: 4))
                XCTAssertEqual(Array(right.prefix(min(4, rightFrames))), Array(repeating: 0.5, count: min(4, rightFrames)))
                if rightFrames > 4 { XCTAssertEqual(Array(right[4..<rightFrames]), Array(repeating: 0, count: rightFrames - 4)) }
                XCTAssertEqual(Array(right.dropFirst(rightFrames)), Array(repeating: -99, count: 8 - rightFrames),
                               "Writes exceeded the right channel's declared length (\(rightFrames), input NI: \(noninterleavedInput))")
            }
        }
    }
}
