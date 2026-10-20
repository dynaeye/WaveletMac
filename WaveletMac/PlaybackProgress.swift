import Foundation

/// Pure geometry and labels for the main-screen dial that replaces the tuning scale
/// while a local file or UPnP item is playing.
struct LocalPlaybackProgress: Equatable {
    var position: TimeInterval
    var duration: TimeInterval

    /// Dragging only makes sense once AVPlayer reported a finite, positive duration.
    var isSeekable: Bool { duration.isFinite && duration > 0 }

    var ratio: Double {
        guard isSeekable, position.isFinite else { return 0 }
        return min(max(position / duration, 0), 1)
    }

    var elapsedLabel: String {
        AudioFile.durationLabel(position.isFinite ? max(0, position) : 0) ?? "0:00"
    }

    var durationLabel: String {
        AudioFile.durationLabel(isSeekable ? duration : nil) ?? "--:--"
    }

    /// Maps a drag position on the dial (or a click ratio) to a seek target.
    func position(atRatio ratio: Double) -> TimeInterval {
        guard isSeekable, ratio.isFinite else { return 0 }
        return min(max(ratio, 0), 1) * duration
    }

    func position(atX x: CGFloat, width: CGFloat) -> TimeInterval {
        guard width > 0 else { return position(atRatio: 0) }
        return position(atRatio: Double(x / width))
    }

    /// Fill level of one cell in the segmented progress row: 1 = fully played,
    /// 0.42 = the cell the playhead is currently inside, 0 = not reached yet.
    static func segmentLevel(index: Int, count: Int, ratio: Double) -> Double {
        guard count > 0, index >= 0, index < count, ratio.isFinite else { return 0.14 }
        let played = min(max(ratio, 0), 1) * Double(count)
        if Double(index + 1) <= played { return 0.82 }
        if Double(index) < played { return 0.42 }
        return 0.14
    }
}
