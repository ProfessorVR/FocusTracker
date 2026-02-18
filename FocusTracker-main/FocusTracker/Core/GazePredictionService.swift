import ARKit
import CoreML
import UIKit

/// On-device gaze prediction using the iTracker CNN (CoreML).
///
/// Replaces the geometric `ScreenMapper` with a learned model that predicts
/// where the user is looking from camera imagery alone. The model takes four
/// inputs — left eye crop, right eye crop, face crop, and a binary face grid —
/// and outputs a 2D gaze point in centimeters relative to the camera, which
/// is then converted to screen coordinates.
///
/// ## Architecture (iTracker, CVPR 2016)
///
/// ```
/// Eye streams (shared weights):
///   Conv 11x11/96 -> Conv 5x5/256 -> Conv 3x3/384 -> Conv 1x1/64 -> FC-128
///
/// Face stream:
///   Conv 11x11/96 -> Conv 5x5/256 -> Conv 3x3/384 -> Conv 1x1/64 -> FC-128 -> FC-64
///
/// Face grid stream:
///   FC-256 -> FC-128
///
/// All streams concatenate -> FC-128 -> FC-2 (x_cm, y_cm)
/// ```
///
/// ## Usage
///
/// ```swift
/// let service = GazePredictionService()
/// if let result = service.predict(frame: arFrame, faceAnchor: faceAnchor) {
///     // result.screenPoint — gaze in screen coordinates
///     // result.isOnScreen — whether the point falls within screen bounds
/// }
/// ```
///
/// ## Model File
///
/// Place `iTracker.mlmodelc` or `iTracker.mlpackage` in the Xcode project.
/// The service loads the model lazily on first prediction. If the model file
/// is absent, `predict()` returns `nil` and callers should fall back to the
/// geometric `ScreenMapper`.
final class GazePredictionService {

    // MARK: - Types

    struct PredictionResult {
        /// Predicted gaze point in screen coordinates (points).
        let screenPoint: CGPoint

        /// Whether the predicted point falls within the visible screen area.
        let isOnScreen: Bool

        /// Raw model output in centimeters relative to the camera.
        let gazeCm: CGPoint

        /// Confidence estimate (0-1). Currently based on face tracking quality.
        let confidence: Float
    }

    // MARK: - Properties

    /// Device screen size in points, used for cm-to-points conversion.
    let screenSize: CGSize

    /// The loaded CoreML model. `nil` if the model file is missing or failed to load.
    private var model: MLModel?

    /// Whether model loading has been attempted (avoid repeated failures).
    private var modelLoadAttempted = false

    /// Face grid generator for producing the 25x25 binary mask input.
    private let faceGridGenerator = FaceGridGenerator()

    /// Optional calibration result to apply on top of CNN predictions.
    private(set) var calibration: CalibrationResult?

    // MARK: - Constants

    /// Input image size expected by iTracker for each crop (eye and face).
    private let inputSize: CGFloat = 224.0

    /// Margin (in points) around screen edges for "on-screen" determination.
    private let onScreenMargin: CGFloat = 40.0

    /// Physical screen width in centimeters (iPhone 15/16 Pro: ~7.08 cm).
    /// Used to convert the model's cm output to screen points.
    private let screenWidthCm: Float = 7.08

    /// Physical screen height in centimeters (iPhone 15/16 Pro: ~15.41 cm).
    private let screenHeightCm: Float = 15.41

    // MARK: - Initialization

    init(screenSize: CGSize? = nil) {
        self.screenSize = screenSize ?? UIScreen.main.bounds.size
        loadModelIfNeeded()
    }

    // MARK: - Public API

    /// Whether the CoreML model is available for predictions.
    var isModelAvailable: Bool {
        loadModelIfNeeded()
        return model != nil
    }

    /// Predicts the on-screen gaze point from an AR frame and face anchor.
    ///
    /// - Parameters:
    ///   - frame: The current `ARFrame` containing the camera image.
    ///   - faceAnchor: The detected `ARFaceAnchor` with face geometry.
    /// - Returns: A `PredictionResult` with screen coordinates, or `nil` if
    ///   the model is unavailable or prediction fails.
    func predict(frame: ARFrame, faceAnchor: ARFaceAnchor) -> PredictionResult? {
        guard let model = self.model else { return nil }

        let pixelBuffer = frame.capturedImage
        let imageWidth = CVPixelBufferGetWidth(pixelBuffer)
        let imageHeight = CVPixelBufferGetHeight(pixelBuffer)

        // Convert face anchor bounding box to pixel coordinates in the camera image.
        // ARKit provides face geometry in the anchor's local coordinate space.
        // We project key face landmarks to 2D image coordinates.
        guard let faceBounds = computeFaceBounds(
            faceAnchor: faceAnchor,
            frame: frame,
            imageWidth: imageWidth,
            imageHeight: imageHeight
        ) else { return nil }

        // Crop the three image inputs.
        guard let faceImage = cropAndResize(pixelBuffer: pixelBuffer, rect: faceBounds.faceRect),
              let leftEyeImage = cropAndResize(pixelBuffer: pixelBuffer, rect: faceBounds.leftEyeRect),
              let rightEyeImage = cropAndResize(pixelBuffer: pixelBuffer, rect: faceBounds.rightEyeRect)
        else { return nil }

        // Generate the 25x25 face grid.
        let faceGrid = faceGridGenerator.generate(
            faceBounds: faceBounds.faceRect,
            imageWidth: imageWidth,
            imageHeight: imageHeight
        )

        // Run CoreML inference.
        guard let prediction = runInference(
            model: model,
            faceImage: faceImage,
            leftEyeImage: leftEyeImage,
            rightEyeImage: rightEyeImage,
            faceGrid: faceGrid
        ) else { return nil }

        // Convert cm output to screen coordinates.
        let screenPoint = cmToScreenPoint(xCm: prediction.x, yCm: prediction.y)

        var finalPoint = screenPoint

        // Apply calibration if available.
        if let cal = calibration {
            finalPoint = cal.apply(to: finalPoint)
        }

        let isOnScreen = finalPoint.x >= -onScreenMargin
            && finalPoint.x <= screenSize.width + onScreenMargin
            && finalPoint.y >= -onScreenMargin
            && finalPoint.y <= screenSize.height + onScreenMargin

        let quality: Float = faceAnchor.isTracked ? 1.0 : 0.3

        return PredictionResult(
            screenPoint: finalPoint,
            isOnScreen: isOnScreen,
            gazeCm: CGPoint(x: CGFloat(prediction.x), y: CGFloat(prediction.y)),
            confidence: quality
        )
    }

    /// Applies a calibration result to improve prediction accuracy.
    func setCalibration(_ cal: CalibrationResult) {
        calibration = cal
    }

    /// Removes the current calibration.
    func clearCalibration() {
        calibration = nil
    }

    // MARK: - Model Loading

    @discardableResult
    private func loadModelIfNeeded() -> Bool {
        guard !modelLoadAttempted else { return model != nil }
        modelLoadAttempted = true

        // Try loading the model from the app bundle.
        // Xcode compiles .mlpackage into .mlmodelc automatically.
        guard let modelURL = Bundle.main.url(forResource: "iTracker", withExtension: "mlmodelc") else {
            print("[GazePredictionService] iTracker.mlmodelc not found in bundle. CNN prediction unavailable.")
            return false
        }

        do {
            let config = MLModelConfiguration()
            config.computeUnits = .all  // Use Neural Engine + GPU + CPU.
            model = try MLModel(contentsOf: modelURL, configuration: config)
            print("[GazePredictionService] iTracker model loaded successfully.")
            return true
        } catch {
            print("[GazePredictionService] Failed to load iTracker model: \(error.localizedDescription)")
            return false
        }
    }

    // MARK: - Face Bounds Computation

    /// Bounding boxes for face and eye crops in pixel coordinates.
    struct FaceBounds {
        let faceRect: CGRect
        let leftEyeRect: CGRect
        let rightEyeRect: CGRect
    }

    /// Projects the face anchor's geometry into the camera image to get
    /// bounding boxes for the face and each eye.
    private func computeFaceBounds(
        faceAnchor: ARFaceAnchor,
        frame: ARFrame,
        imageWidth: Int,
        imageHeight: Int
    ) -> FaceBounds? {
        let camera = frame.camera
        let viewportSize = CGSize(width: imageWidth, height: imageHeight)

        // Project the face center (anchor origin) to 2D.
        let faceCenter3D = faceAnchor.transform.columns.3
        let facePoint = camera.projectPoint(
            simd_float3(faceCenter3D.x, faceCenter3D.y, faceCenter3D.z),
            orientation: .portrait,
            viewportSize: viewportSize
        )

        // Project eye positions (from the eye transforms relative to face anchor).
        let leftEyeWorld = faceAnchor.transform * faceAnchor.leftEyeTransform
        let rightEyeWorld = faceAnchor.transform * faceAnchor.rightEyeTransform

        let leftEyePoint = camera.projectPoint(
            simd_float3(leftEyeWorld.columns.3.x, leftEyeWorld.columns.3.y, leftEyeWorld.columns.3.z),
            orientation: .portrait,
            viewportSize: viewportSize
        )
        let rightEyePoint = camera.projectPoint(
            simd_float3(rightEyeWorld.columns.3.x, rightEyeWorld.columns.3.y, rightEyeWorld.columns.3.z),
            orientation: .portrait,
            viewportSize: viewportSize
        )

        // Estimate face size from the inter-eye distance.
        let eyeDistance = hypot(rightEyePoint.x - leftEyePoint.x, rightEyePoint.y - leftEyePoint.y)
        guard eyeDistance > 10 else { return nil }  // Face too small or degenerate.

        // Face crop: ~2.5x the inter-eye distance, centered on face.
        let faceSize = eyeDistance * 2.5
        let faceRect = CGRect(
            x: facePoint.x - faceSize / 2,
            y: facePoint.y - faceSize / 2,
            width: faceSize,
            height: faceSize
        ).intersection(CGRect(x: 0, y: 0, width: CGFloat(imageWidth), height: CGFloat(imageHeight)))

        // Eye crops: ~1.2x the inter-eye distance, centered on each eye.
        let eyeCropSize = eyeDistance * 1.2
        let leftEyeRect = CGRect(
            x: leftEyePoint.x - eyeCropSize / 2,
            y: leftEyePoint.y - eyeCropSize / 2,
            width: eyeCropSize,
            height: eyeCropSize
        ).intersection(CGRect(x: 0, y: 0, width: CGFloat(imageWidth), height: CGFloat(imageHeight)))

        let rightEyeRect = CGRect(
            x: rightEyePoint.x - eyeCropSize / 2,
            y: rightEyePoint.y - eyeCropSize / 2,
            width: eyeCropSize,
            height: eyeCropSize
        ).intersection(CGRect(x: 0, y: 0, width: CGFloat(imageWidth), height: CGFloat(imageHeight)))

        guard faceRect.width > 0, faceRect.height > 0,
              leftEyeRect.width > 0, leftEyeRect.height > 0,
              rightEyeRect.width > 0, rightEyeRect.height > 0
        else { return nil }

        return FaceBounds(
            faceRect: faceRect,
            leftEyeRect: leftEyeRect,
            rightEyeRect: rightEyeRect
        )
    }

    // MARK: - Image Cropping

    /// Crops a region from a pixel buffer and resizes to 224x224.
    private func cropAndResize(pixelBuffer: CVPixelBuffer, rect: CGRect) -> CGImage? {
        let ciImage = CIImage(cvPixelBuffer: pixelBuffer)
        let cropped = ciImage.cropped(to: rect)

        // Scale to 224x224.
        let scaleX = inputSize / rect.width
        let scaleY = inputSize / rect.height
        let scaled = cropped.transformed(by: CGAffineTransform(scaleX: scaleX, y: scaleY))

        let context = CIContext(options: [.useSoftwareRenderer: false])
        let outputRect = CGRect(x: 0, y: 0, width: inputSize, height: inputSize)

        return context.createCGImage(scaled, from: outputRect)
    }

    // MARK: - CoreML Inference

    /// Raw prediction output from the model.
    private struct RawPrediction {
        let x: Float  // cm
        let y: Float  // cm
    }

    /// Runs the iTracker CoreML model with the four prepared inputs.
    ///
    /// The model expects:
    /// - `image_face`: 224x224 RGB face crop
    /// - `image_left`: 224x224 RGB left eye crop
    /// - `image_right`: 224x224 RGB right eye crop
    /// - `facegrid`: 625-element (25x25) binary float array
    ///
    /// Output: 2-element array [x_cm, y_cm]
    private func runInference(
        model: MLModel,
        faceImage: CGImage,
        leftEyeImage: CGImage,
        rightEyeImage: CGImage,
        faceGrid: MLMultiArray
    ) -> RawPrediction? {
        do {
            // Create MLFeatureProvider with all four inputs.
            let faceBuffer = try cgImageToPixelBuffer(faceImage)
            let leftBuffer = try cgImageToPixelBuffer(leftEyeImage)
            let rightBuffer = try cgImageToPixelBuffer(rightEyeImage)

            let input = iTrackerInput(
                image_face: faceBuffer,
                image_left: leftBuffer,
                image_right: rightBuffer,
                facegrid: faceGrid
            )

            let output = try model.prediction(from: input)

            // Extract the 2D gaze output.
            guard let gazeOutput = output.featureValue(for: "output")?.multiArrayValue,
                  gazeOutput.count >= 2
            else { return nil }

            let xCm = gazeOutput[0].floatValue
            let yCm = gazeOutput[1].floatValue

            return RawPrediction(x: xCm, y: yCm)
        } catch {
            print("[GazePredictionService] Inference failed: \(error.localizedDescription)")
            return nil
        }
    }

    // MARK: - Coordinate Conversion

    /// Converts the model's centimeter output to screen points.
    ///
    /// The model outputs gaze position in centimeters relative to the camera:
    /// - Positive X = rightward (from user's perspective)
    /// - Positive Y = downward
    ///
    /// Screen coordinates:
    /// - (0,0) = top-left
    /// - (+X) = rightward
    /// - (+Y) = downward
    private func cmToScreenPoint(xCm: Float, yCm: Float) -> CGPoint {
        // Map cm to normalized screen position.
        // The camera is at the top center of the screen.
        // xCm = 0 corresponds to the camera (screen center X).
        // yCm = 0 corresponds to the camera position (top of screen).

        let normalizedX = (xCm / screenWidthCm) + 0.5
        let normalizedY = yCm / screenHeightCm

        let screenX = CGFloat(normalizedX) * screenSize.width
        let screenY = CGFloat(normalizedY) * screenSize.height

        return CGPoint(x: screenX, y: screenY)
    }

    // MARK: - Pixel Buffer Conversion

    /// Converts a CGImage to a CVPixelBuffer suitable for CoreML input.
    private func cgImageToPixelBuffer(_ image: CGImage) throws -> CVPixelBuffer {
        let width = Int(inputSize)
        let height = Int(inputSize)

        var pixelBuffer: CVPixelBuffer?
        let attrs: [CFString: Any] = [
            kCVPixelBufferCGImageCompatibilityKey: true,
            kCVPixelBufferCGBitmapContextCompatibilityKey: true
        ]

        let status = CVPixelBufferCreate(
            kCFAllocatorDefault,
            width, height,
            kCVPixelFormatType_32BGRA,
            attrs as CFDictionary,
            &pixelBuffer
        )

        guard status == kCVReturnSuccess, let buffer = pixelBuffer else {
            throw GazePredictionError.pixelBufferCreationFailed
        }

        CVPixelBufferLockBaseAddress(buffer, [])
        defer { CVPixelBufferUnlockBaseAddress(buffer, []) }

        guard let context = CGContext(
            data: CVPixelBufferGetBaseAddress(buffer),
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: CVPixelBufferGetBytesPerRow(buffer),
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.noneSkipFirst.rawValue | CGBitmapInfo.byteOrder32Little.rawValue
        ) else {
            throw GazePredictionError.pixelBufferCreationFailed
        }

        context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
        return buffer
    }
}

// MARK: - Error Types

enum GazePredictionError: Error {
    case pixelBufferCreationFailed
    case modelNotLoaded
}

// MARK: - iTracker MLFeatureProvider

/// Custom feature provider for the iTracker multi-input CoreML model.
private class iTrackerInput: MLFeatureProvider {
    let image_face: CVPixelBuffer
    let image_left: CVPixelBuffer
    let image_right: CVPixelBuffer
    let facegrid: MLMultiArray

    var featureNames: Set<String> {
        ["image_face", "image_left", "image_right", "facegrid"]
    }

    init(image_face: CVPixelBuffer, image_left: CVPixelBuffer, image_right: CVPixelBuffer, facegrid: MLMultiArray) {
        self.image_face = image_face
        self.image_left = image_left
        self.image_right = image_right
        self.facegrid = facegrid
    }

    func featureValue(for featureName: String) -> MLFeatureValue? {
        switch featureName {
        case "image_face":
            return MLFeatureValue(pixelBuffer: image_face)
        case "image_left":
            return MLFeatureValue(pixelBuffer: image_left)
        case "image_right":
            return MLFeatureValue(pixelBuffer: image_right)
        case "facegrid":
            return MLFeatureValue(multiArray: facegrid)
        default:
            return nil
        }
    }
}
