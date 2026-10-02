import Foundation

/// The controls available for the current phase, in their displayed order.
enum PomodoroControl: String, Identifiable {
    case addFiveMinutes, startFocus, startBreak, pause, resume, skip, skipBreak, takeBreak, endFocus

    var id: String { rawValue }

    var title: String {
        switch self {
        case .addFiveMinutes: "+ 5 mins"
        case .startFocus: "Start Focus"
        case .startBreak: "Start Break"
        case .pause: "Pause"
        case .resume: "Resume"
        case .skip: "Skip"
        case .skipBreak: "Skip Break"
        case .takeBreak: "Take Break"
        case .endFocus: "End Focus"
        }
    }

    var isPrimary: Bool {
        switch self {
        case .startFocus, .startBreak, .pause, .resume: true
        default: false
        }
    }
}

extension PomodoroState {
    var controls: [PomodoroControl] {
        switch run {
        case .ready:
            phase.isBreak ? [.addFiveMinutes, .startBreak, .skip] : [.addFiveMinutes, .startFocus]
        case .running:
            phase.isBreak ? [.pause, .skipBreak] : [.pause]
        case .paused:
            phase.isBreak ? [.resume, .startFocus] : [.resume, .takeBreak, .endFocus]
        }
    }
}
