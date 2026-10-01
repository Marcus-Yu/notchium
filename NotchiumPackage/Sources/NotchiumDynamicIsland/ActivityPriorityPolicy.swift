/// The single semantic priority table and arbitration order for every activity.
///
/// 1. Transients (events) interrupt baselines (persistent/condition state such as Music):
///    a volume change briefly takes the notch, then Music returns without being recreated.
/// 2. Among transients, higher priority wins; at equal priority the latest update wins.
///    Interrupted transients stay live underneath until their own absolute deadline.
/// 3. Replaceable HUDs (volume/mute) exist only while presented: never queued, never resumed.
/// 4. Among baselines, higher priority wins; at equal priority the earliest stays put.
/// 5. The stable key breaks any remaining tie, so ordering is always deterministic.
///
/// Secondary: the highest-ranked persistent activity (with a visible minimal form) that is not
/// already primary — so an active transfer outranks Music. Beside a persistent primary, or beside a
/// Calendar alert (where Music is never the chip: it already lives in the banner's top row).
/// Short system transients own the whole compact presentation; nothing sits beside them.
public enum ActivityPriorityPolicy {
    /// How long paused content stays in the collapsed notch. Music's flanks leave once local audio
    /// has been silent this long; a paused timer leaves after the same interval. Hiding is
    /// presentation only: the paused session itself is untouched.
    public static let pausedPresentationExpiry: Duration = .milliseconds(250)

    public static func priority(for kind: NotchNotification.Kind) -> NotchActivityPriority {
        switch kind {
        case .criticalBattery: .critical
        case .reminder5, .lowBattery, .screenshot, .focusTimerComplete: .high
        case .reminder30, .reminder60, .outputDeviceChanged, .charging, .powerDisconnected,
             .transferFinished, .transferFailed, .focusModeChanged: .medium
        // An active transfer is a baseline: it outranks Music and every transient interrupts it.
        case .transferActive: .medium
        // A running focus timer is a baseline like a transfer. Its "Music" preference ranks it at
        // Music's level, where visible Music keeps the notch and the timer becomes the chip.
        case .focusTimer: .medium
        case .focusTimerBesideMusic: .low
        case .volume, .mute, .actionSucceeded, .actionFailed, .reminderAdded, .shelfAdded: .low
        }
    }

    public static func priority(for kind: NotchActivityKind) -> NotchActivityPriority {
        switch kind {
        case .media, .systemHUD: .low
        case .charging, .audioDevice, .download, .screenshot, .calendar, .pomodoro: .medium
        case .focus, .battery, .meeting, .clipboard: .high
        case .notification: .critical
        }
    }

    static func outranks(_ lhs: ActivityCoordinator.Entry, _ rhs: ActivityCoordinator.Entry) -> Bool {
        let left = lhs.activity, right = rhs.activity
        if left.lifetime.isBaseline != right.lifetime.isBaseline { return !left.lifetime.isBaseline }
        if left.priority != right.priority { return left.priority > right.priority }
        if left.lifetime.isBaseline {
            // Equal baselines: one that can be seen (it has a minimal form) before one that cannot,
            // then Music, which draws its own flanks; a hidden paused track never hides the rest.
            if (left.minimal != nil) != (right.minimal != nil) { return left.minimal != nil }
            let leftMedia = left.presentationStyle == .mediaSides, rightMedia = right.presentationStyle == .mediaSides
            if leftMedia != rightMedia { return leftMedia }
        }
        if lhs.sequence != rhs.sequence {
            return left.lifetime.isBaseline ? lhs.sequence < rhs.sequence : lhs.sequence > rhs.sequence
        }
        return left.key.rawValue < right.key.rawValue
    }

    /// "Reduce interruptions while Focus is on": cosmetic or routine events stay quiet. Critical
    /// battery, imminent meetings, timer completion, transfers, the user's own actions and the
    /// Focus change itself still present.
    public static func isQuietedDuringFocus(_ kind: NotchNotification.Kind) -> Bool {
        switch kind {
        case .reminder60, .reminder30, .outputDeviceChanged, .charging, .powerDisconnected, .screenshot: true
        default: false
        }
    }

    /// Volume-style feedback is momentary: once something else holds the notch it is stale.
    static func isReplaceable(_ entry: ActivityCoordinator.Entry) -> Bool {
        guard !entry.activity.lifetime.isBaseline else { return false }
        if let kind = entry.notification?.kind { return kind == .volume || kind == .mute }
        return entry.activity.kind == .systemHUD
    }

    /// `ranked` is best-first. Media publishes a minimal form only while its collapsed flanks are
    /// really visible, so a hidden primary never strands a chip and hidden Music is never chosen.
    static func secondary(beside primary: ActivityCoordinator.Entry,
                          among ranked: [ActivityCoordinator.Entry]) -> ActivityCoordinator.Entry? {
        // A primary that already shows Music's artwork and waveform (the focus timer) never
        // repeats Music as a chip beside itself.
        let embedsMedia = primary.notification?.content.compactActivity?.blendsWithMedia == true
        let persistent = ranked.filter {
            $0.activity.lifetime.isBaseline && $0.activity.minimal != nil && $0.activity.key != primary.activity.key
                && !(embedsMedia && $0.activity.presentationStyle == .mediaSides)
        }
        if primary.activity.lifetime.isBaseline {
            return primary.activity.minimal != nil ? persistent.first : nil
        }
        guard primary.activity.presentationStyle == .downwardBanner, primary.activity.family == .calendar else {
            return nil
        }
        return persistent.first { $0.activity.presentationStyle != .mediaSides }
    }
}
