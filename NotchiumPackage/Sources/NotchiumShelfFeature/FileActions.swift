import AppKit
import UniformTypeIdentifiers
import NotchiumDynamicIsland

public enum ShareOutcome: Equatable, Sendable {
    /// Apple's native sharing UI is showing; the user completes or cancels it there.
    case presented
    /// No service can take these items (e.g. AirDrop off/unsupported, or nothing shareable).
    case unavailable
}

/// Native file actions. Sharing only ever presents Apple's own UI: AirDrop is the public
/// `NSSharingService.sendViaAirDrop`; general sharing uses an owned `NSSharingServicePicker`.
@MainActor public protocol FileActionPerforming: AnyObject {
    func open(_ urls: [URL])
    func reveal(_ urls: [URL])
    func copyFiles(_ urls: [URL])
    func copyPaths(_ urls: [URL])
    func airDrop(_ urls: [URL]) -> ShareOutcome
    func airDrop(_ urls: [URL], from view: NSView?, interaction: NotchAuxiliaryInteractionHandler) -> ShareOutcome
    func share(_ urls: [URL], from view: NSView, interaction: NotchAuxiliaryInteractionHandler) -> ShareOutcome
    func chooseFiles() async -> [URL]
    /// Files & Folders privacy settings, for recovering denied folder access.
    func openPrivacySettings()
}

extension FileActionPerforming {
    public func airDrop(_ urls: [URL], from view: NSView?, interaction: NotchAuxiliaryInteractionHandler) -> ShareOutcome {
        airDrop(urls)
    }
    public func share(_ urls: [URL], from view: NSView, interaction: NotchAuxiliaryInteractionHandler) -> ShareOutcome {
        .unavailable
    }
}

@MainActor public final class NativeFileActions: FileActionPerforming {
    private let workspace: NSWorkspace
    private let pasteboard: NSPasteboard
    private let sharing = NativeFileSharing()

    public init(workspace: NSWorkspace = .shared, pasteboard: NSPasteboard = .general) {
        self.workspace = workspace
        self.pasteboard = pasteboard
    }

    public func open(_ urls: [URL]) { urls.forEach { workspace.open($0) } }

    public func reveal(_ urls: [URL]) { workspace.activateFileViewerSelecting(urls) }

    /// File references, plus image data for single images so pasting into editors works.
    /// Only the file's existing bytes are read, on this explicit action; nothing is decoded.
    public func copyFiles(_ urls: [URL]) {
        pasteboard.clearContents()
        pasteboard.writeObjects(urls as [NSURL])
        if urls.count == 1, let url = urls.first,
           let type = UTType(filenameExtension: url.pathExtension), type.conforms(to: .image),
           let data = try? Data(contentsOf: url, options: .mappedIfSafe) {
            pasteboard.setData(data, forType: NSPasteboard.PasteboardType(type.identifier))
        }
    }

    public func copyPaths(_ urls: [URL]) {
        pasteboard.clearContents()
        pasteboard.setString(urls.map(\.path).joined(separator: "\n"), forType: .string)
    }

    public func airDrop(_ urls: [URL]) -> ShareOutcome {
        sharing.airDrop(urls, from: nil, interaction: .init())
    }

    public func airDrop(_ urls: [URL], from view: NSView?, interaction: NotchAuxiliaryInteractionHandler) -> ShareOutcome {
        sharing.airDrop(urls, from: view, interaction: interaction)
    }

    public func share(_ urls: [URL], from view: NSView, interaction: NotchAuxiliaryInteractionHandler) -> ShareOutcome {
        sharing.share(urls, from: view, interaction: interaction)
    }

    public func chooseFiles() async -> [URL] {
        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = true
        panel.canChooseDirectories = true
        panel.canChooseFiles = true
        panel.title = "Add to Shelf"
        panel.prompt = "Add"
        return await panel.begin() == .OK ? panel.urls : []
    }

    public func openPrivacySettings() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_FilesAndFolders") {
            workspace.open(url)
        }
    }

    /// The system's own AirDrop icon, when the service exists on this Mac.
    public static let airDropImage: NSImage? = NSSharingService(named: .sendViaAirDrop)?.image
}
