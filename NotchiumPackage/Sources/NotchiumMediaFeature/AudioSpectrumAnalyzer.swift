import Accelerate
import Foundation

/// Queue-confined FFT analysis. Stereo power is combined after the FFT so opposite-phase
/// channels cannot cancel. No samples leave this analyzer or get written to disk.
final class AudioSpectrumAnalyzer {
    static let sampleCount = 2048
    static let minimum: CGFloat = 0.12
    static let bands: [(Double, Double)] = [
        (60, 120), (120, 250), (250, 500), (500, 1000),
        (1000, 2000), (2000, 5000), (5000, 12000)
    ]
    private let setup = vDSP_create_fftsetup(11, FFTRadix(kFFTRadix2))!
    private var window = [Float](repeating: 0, count: sampleCount)
    private var smoothed = [CGFloat](repeating: minimum, count: 7)

    init() {
        vDSP_hann_window(&window, vDSP_Length(Self.sampleCount), Int32(vDSP_HANN_NORM))
    }
    deinit { vDSP_destroy_fftsetup(setup) }

    func levels(channels: [[Float]], sampleRate: Double) -> [CGFloat] {
        let count = Self.sampleCount
        guard !channels.isEmpty, sampleRate > 0,
              channels.allSatisfy({ $0.count == count }) else { return smoothed }
        var power = [Float](repeating: 0, count: count / 2)
        for channel in channels {
            var real = [Float](repeating: 0, count: count)
            var imaginary = real
            vDSP_vmul(channel, 1, window, 1, &real, 1, vDSP_Length(count))
            real.withUnsafeMutableBufferPointer { re in
                imaginary.withUnsafeMutableBufferPointer { im in
                    var split = DSPSplitComplex(realp: re.baseAddress!, imagp: im.baseAddress!)
                    vDSP_fft_zip(setup, &split, 1, 11, FFTDirection(FFT_FORWARD))
                    var spectrum = [Float](repeating: 0, count: count / 2)
                    vDSP_zvmags(&split, 1, &spectrum, 1, vDSP_Length(count / 2))
                    vDSP_vadd(power, 1, spectrum, 1, &power, 1, vDSP_Length(count / 2))
                }
            }
        }
        for (index, band) in Self.bands.enumerated() {
            let lower = max(1, Int(ceil(band.0 * Double(count) / sampleRate)))
            let upper = min(count / 2, Int(ceil(band.1 * Double(count) / sampleRate)))
            var energy: Float = 0
            if upper > lower {
                power.withUnsafeBufferPointer {
                    vDSP_sve($0.baseAddress! + lower, 1, &energy, vDSP_Length(upper - lower))
                }
            }
            let rms = sqrt(Double(energy) / (Double(count * count) * Double(channels.count)))
            let decibels = 20 * log10(max(rms, 0.000001))
            let target = CGFloat(min(1, max(Double(Self.minimum), (decibels + 60) / 48)))
            let coefficient: CGFloat = target > smoothed[index] ? 0.75 : 0.16
            smoothed[index] += coefficient * (target - smoothed[index])
        }
        return smoothed
    }
}
