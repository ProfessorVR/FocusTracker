import Foundation
import simd

struct GazeFrame: Codable {
    let timestamp: TimeInterval
    let gazePointX: CGFloat
    let gazePointY: CGFloat
    let leftEyePosition: simd_float3
    let rightEyePosition: simd_float3
    let lookAtPoint: simd_float3
    let leftBlinkValue: Float   // 0.0 - 1.0
    let rightBlinkValue: Float  // 0.0 - 1.0
    let headEulerX: Float
    let headEulerY: Float
    let headEulerZ: Float
    let isOnScreen: Bool
    let trackingQuality: Float  // 0.0 - 1.0

    var screenPoint: CGPoint {
        CGPoint(x: gazePointX, y: gazePointY)
    }

    var averageBlinkValue: Float {
        (leftBlinkValue + rightBlinkValue) / 2.0
    }

    // MARK: - Custom Codable for simd_float3

    enum CodingKeys: String, CodingKey {
        case timestamp
        case gazePointX, gazePointY
        case leftEyePosition, rightEyePosition, lookAtPoint
        case leftBlinkValue, rightBlinkValue
        case headEulerX, headEulerY, headEulerZ
        case isOnScreen
        case trackingQuality
    }

    init(
        timestamp: TimeInterval,
        gazePointX: CGFloat,
        gazePointY: CGFloat,
        leftEyePosition: simd_float3,
        rightEyePosition: simd_float3,
        lookAtPoint: simd_float3,
        leftBlinkValue: Float,
        rightBlinkValue: Float,
        headEulerX: Float,
        headEulerY: Float,
        headEulerZ: Float,
        isOnScreen: Bool,
        trackingQuality: Float
    ) {
        self.timestamp = timestamp
        self.gazePointX = gazePointX
        self.gazePointY = gazePointY
        self.leftEyePosition = leftEyePosition
        self.rightEyePosition = rightEyePosition
        self.lookAtPoint = lookAtPoint
        self.leftBlinkValue = leftBlinkValue
        self.rightBlinkValue = rightBlinkValue
        self.headEulerX = headEulerX
        self.headEulerY = headEulerY
        self.headEulerZ = headEulerZ
        self.isOnScreen = isOnScreen
        self.trackingQuality = trackingQuality
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)

        timestamp = try container.decode(TimeInterval.self, forKey: .timestamp)
        gazePointX = try container.decode(CGFloat.self, forKey: .gazePointX)
        gazePointY = try container.decode(CGFloat.self, forKey: .gazePointY)

        let leftEye = try container.decode([Float].self, forKey: .leftEyePosition)
        leftEyePosition = simd_float3(leftEye[0], leftEye[1], leftEye[2])

        let rightEye = try container.decode([Float].self, forKey: .rightEyePosition)
        rightEyePosition = simd_float3(rightEye[0], rightEye[1], rightEye[2])

        let lookAt = try container.decode([Float].self, forKey: .lookAtPoint)
        lookAtPoint = simd_float3(lookAt[0], lookAt[1], lookAt[2])

        leftBlinkValue = try container.decode(Float.self, forKey: .leftBlinkValue)
        rightBlinkValue = try container.decode(Float.self, forKey: .rightBlinkValue)
        headEulerX = try container.decode(Float.self, forKey: .headEulerX)
        headEulerY = try container.decode(Float.self, forKey: .headEulerY)
        headEulerZ = try container.decode(Float.self, forKey: .headEulerZ)
        isOnScreen = try container.decode(Bool.self, forKey: .isOnScreen)
        trackingQuality = try container.decode(Float.self, forKey: .trackingQuality)
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)

        try container.encode(timestamp, forKey: .timestamp)
        try container.encode(gazePointX, forKey: .gazePointX)
        try container.encode(gazePointY, forKey: .gazePointY)

        try container.encode(
            [leftEyePosition.x, leftEyePosition.y, leftEyePosition.z],
            forKey: .leftEyePosition
        )
        try container.encode(
            [rightEyePosition.x, rightEyePosition.y, rightEyePosition.z],
            forKey: .rightEyePosition
        )
        try container.encode(
            [lookAtPoint.x, lookAtPoint.y, lookAtPoint.z],
            forKey: .lookAtPoint
        )

        try container.encode(leftBlinkValue, forKey: .leftBlinkValue)
        try container.encode(rightBlinkValue, forKey: .rightBlinkValue)
        try container.encode(headEulerX, forKey: .headEulerX)
        try container.encode(headEulerY, forKey: .headEulerY)
        try container.encode(headEulerZ, forKey: .headEulerZ)
        try container.encode(isOnScreen, forKey: .isOnScreen)
        try container.encode(trackingQuality, forKey: .trackingQuality)
    }
}
