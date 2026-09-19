import Foundation

public struct CameraCaptureFormatCandidate: Equatable, Sendable {
    public let width: Int
    public let height: Int
    public let maxFrameRate: Double
    public let pixelFormatScore: Int

    public init(width: Int,
                height: Int,
                maxFrameRate: Double,
                pixelFormatScore: Int = 0) {
        self.width = width
        self.height = height
        self.maxFrameRate = maxFrameRate
        self.pixelFormatScore = pixelFormatScore
    }

    public var pixelCount: Int {
        width * height
    }
}

public enum CameraCaptureFormatPolicy {
    public static func preferredIndex(in candidates: [CameraCaptureFormatCandidate]) -> Int? {
        var preferred: (offset: Int, element: CameraCaptureFormatCandidate)?
        for (offset, candidate) in candidates.enumerated() {
            guard isUsable(candidate) else { continue }
            guard let current = preferred else {
                preferred = (offset, candidate)
                continue
            }
            if isPreferred((offset, candidate), current) {
                preferred = (offset, candidate)
            }
        }
        return preferred?.offset
    }

    private static func isUsable(_ candidate: CameraCaptureFormatCandidate) -> Bool {
        candidate.width > 0
            && candidate.height > 0
            && candidate.maxFrameRate.isFinite
            && candidate.maxFrameRate >= 1
    }

    private static func isPreferred(
        _ lhs: (offset: Int, element: CameraCaptureFormatCandidate),
        _ rhs: (offset: Int, element: CameraCaptureFormatCandidate)
    ) -> Bool {
        if lhs.element.pixelCount != rhs.element.pixelCount {
            return lhs.element.pixelCount > rhs.element.pixelCount // mutation:skip: the preceding != guard makes >= equivalent
        }
        if lhs.element.maxFrameRate != rhs.element.maxFrameRate {
            return lhs.element.maxFrameRate > rhs.element.maxFrameRate // mutation:skip: the preceding != guard makes >= equivalent
        }
        if lhs.element.pixelFormatScore != rhs.element.pixelFormatScore {
            return lhs.element.pixelFormatScore > rhs.element.pixelFormatScore // mutation:skip: the preceding != guard makes >= equivalent
        }
        return lhs.offset < rhs.offset // mutation:skip: distinct enumerated offsets make <= equivalent
    }
}
