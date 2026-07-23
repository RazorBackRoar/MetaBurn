import Foundation

/// Pure rules for when a video clean must fail rather than ship silent output.
public enum AudioPreservation: Sendable {
    /// When mute is off and the source had audio, at least one track must survive remux.
    public static func requiresFailure(
        sourceAudioTrackCount: Int,
        preservedAudioTrackCount: Int,
        muteAudio: Bool
    ) -> Bool {
        !muteAudio && sourceAudioTrackCount > 0 && preservedAudioTrackCount == 0
    }
}
