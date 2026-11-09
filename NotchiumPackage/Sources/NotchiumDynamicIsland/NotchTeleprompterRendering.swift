import SwiftUI

/// The shell owns visibility and navigation; the feature owns reading and capture.
@MainActor public protocol NotchTeleprompterRendering: AnyObject {
    var meetingSuggested: Bool { get }
    var isReading: Bool { get }
    func expandedTeleprompter(prepareToRead: @escaping @MainActor () -> Void) -> AnyView
    func setReadingVisible(_ visible: Bool, source: String)
}
