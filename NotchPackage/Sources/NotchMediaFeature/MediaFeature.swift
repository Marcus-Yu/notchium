import NotchCore
import NotchServices

public enum MediaFeature: FeatureModule {
    public static let descriptor = FeatureDescriptor(
        id: .media,
        name: "Media Center",
        summary: "Provider-neutral playback state and command presentation.",
        requiredPermissions: [.appleMusic, .spotifyAccount, .systemAudioRecording]
    )
}
