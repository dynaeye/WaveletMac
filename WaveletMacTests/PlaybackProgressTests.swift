import Foundation
import XCTest
@testable import WaveletMac

final class PlaybackProgressTests: XCTestCase {
    func testRatioTracksPositionAndClamps() {
        XCTAssertEqual(LocalPlaybackProgress(position: 30, duration: 60).ratio, 0.5, accuracy: 0.0001)
        XCTAssertEqual(LocalPlaybackProgress(position: -5, duration: 60).ratio, 0, accuracy: 0.0001)
        XCTAssertEqual(LocalPlaybackProgress(position: 90, duration: 60).ratio, 1, accuracy: 0.0001)
    }

    func testUnknownDurationIsNotSeekable() {
        let unknown = LocalPlaybackProgress(position: 12, duration: 0)
        XCTAssertFalse(unknown.isSeekable)
        XCTAssertEqual(unknown.ratio, 0, accuracy: 0.0001)
        XCTAssertEqual(unknown.position(atRatio: 0.5), 0, accuracy: 0.0001)
        XCTAssertEqual(unknown.durationLabel, "--:--")

        let invalid = LocalPlaybackProgress(position: .nan, duration: .infinity)
        XCTAssertFalse(invalid.isSeekable)
        XCTAssertEqual(invalid.ratio, 0, accuracy: 0.0001)
        XCTAssertEqual(invalid.elapsedLabel, "0:00")
    }

    func testSeekTargetMapsAndClampsDragPosition() {
        let progress = LocalPlaybackProgress(position: 0, duration: 200)
        XCTAssertEqual(progress.position(atRatio: 0.25), 50, accuracy: 0.0001)
        XCTAssertEqual(progress.position(atRatio: -1), 0, accuracy: 0.0001)
        XCTAssertEqual(progress.position(atRatio: 2), 200, accuracy: 0.0001)
        XCTAssertEqual(progress.position(atRatio: .nan), 0, accuracy: 0.0001)
    }

    func testDragPositionUsesTrackWidth() {
        let progress = LocalPlaybackProgress(position: 0, duration: 120)
        XCTAssertEqual(progress.position(atX: 60, width: 240), 30, accuracy: 0.0001)
        XCTAssertEqual(progress.position(atX: 240, width: 240), 120, accuracy: 0.0001)
        XCTAssertEqual(progress.position(atX: 10, width: 0), 0, accuracy: 0.0001)
    }

    func testLabelsShowElapsedAndTotal() {
        XCTAssertEqual(LocalPlaybackProgress(position: 61, duration: 605).elapsedLabel, "1:01")
        XCTAssertEqual(LocalPlaybackProgress(position: 61, duration: 605).durationLabel, "10:05")
        XCTAssertEqual(LocalPlaybackProgress(position: 3725, duration: 3725).elapsedLabel, "1:02:05")
    }

    func testSegmentLevelsFillProgressively() {
        XCTAssertEqual(LocalPlaybackProgress.segmentLevel(index: 0, count: 10, ratio: 0.35), 0.82, accuracy: 0.0001)
        XCTAssertEqual(LocalPlaybackProgress.segmentLevel(index: 2, count: 10, ratio: 0.35), 0.82, accuracy: 0.0001)
        XCTAssertEqual(LocalPlaybackProgress.segmentLevel(index: 3, count: 10, ratio: 0.35), 0.42, accuracy: 0.0001)
        XCTAssertEqual(LocalPlaybackProgress.segmentLevel(index: 4, count: 10, ratio: 0.35), 0.14, accuracy: 0.0001)
        XCTAssertEqual(LocalPlaybackProgress.segmentLevel(index: 9, count: 10, ratio: 1), 0.82, accuracy: 0.0001)
        XCTAssertEqual(LocalPlaybackProgress.segmentLevel(index: 0, count: 10, ratio: 0), 0.14, accuracy: 0.0001)
    }

    func testSegmentLevelsRejectInvalidGeometry() {
        XCTAssertEqual(LocalPlaybackProgress.segmentLevel(index: 0, count: 0, ratio: 0.5), 0.14, accuracy: 0.0001)
        XCTAssertEqual(LocalPlaybackProgress.segmentLevel(index: -1, count: 10, ratio: 0.5), 0.14, accuracy: 0.0001)
        XCTAssertEqual(LocalPlaybackProgress.segmentLevel(index: 10, count: 10, ratio: 0.5), 0.14, accuracy: 0.0001)
        XCTAssertEqual(LocalPlaybackProgress.segmentLevel(index: 0, count: 10, ratio: .nan), 0.14, accuracy: 0.0001)
    }
}
