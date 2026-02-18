import CoreML
import Foundation

/// Generates the 25x25 binary face grid used as the fourth input to iTracker.
///
/// The face grid encodes the position and size of the detected face within the
/// full camera frame. Each cell in the 25x25 grid is set to 1.0 if the face
/// bounding box overlaps that cell, and 0.0 otherwise.
///
/// This gives the model implicit information about head position and distance
/// from the camera without requiring explicit depth data.
///
/// ## Reference
///
/// Krafka et al., "Eye Tracking for Everyone," CVPR 2016.
/// Section 3.2: "We also provide the network with a binary face grid that
/// indicates the location and size of the head within the original image frame."
final class FaceGridGenerator {

    // MARK: - Constants

    /// Grid dimensions (25x25 as specified in the iTracker paper).
    let gridSize = 25

    // MARK: - Public API

    /// Generates a 25x25 binary face grid from the face bounding box.
    ///
    /// - Parameters:
    ///   - faceBounds: The face bounding box in pixel coordinates.
    ///   - imageWidth: The full camera image width in pixels.
    ///   - imageHeight: The full camera image height in pixels.
    /// - Returns: An `MLMultiArray` of shape [625] (flattened 25x25) with
    ///   Float32 values of 0.0 or 1.0.
    func generate(faceBounds: CGRect, imageWidth: Int, imageHeight: Int) -> MLMultiArray {
        let grid = try! MLMultiArray(shape: [NSNumber(value: gridSize * gridSize)], dataType: .float32)

        guard imageWidth > 0, imageHeight > 0 else {
            return grid  // All zeros.
        }

        // Normalize face bounds to [0, 1] relative to the image.
        let normX = faceBounds.origin.x / CGFloat(imageWidth)
        let normY = faceBounds.origin.y / CGFloat(imageHeight)
        let normW = faceBounds.width / CGFloat(imageWidth)
        let normH = faceBounds.height / CGFloat(imageHeight)

        // Determine which grid cells the face overlaps.
        let cellSize = 1.0 / CGFloat(gridSize)

        for row in 0..<gridSize {
            for col in 0..<gridSize {
                let cellX = CGFloat(col) * cellSize
                let cellY = CGFloat(row) * cellSize

                // Check if this cell overlaps with the face bounding box.
                let overlapX = cellX < (normX + normW) && (cellX + cellSize) > normX
                let overlapY = cellY < (normY + normH) && (cellY + cellSize) > normY

                let index = row * gridSize + col
                grid[index] = NSNumber(value: (overlapX && overlapY) ? Float(1.0) : Float(0.0))
            }
        }

        return grid
    }
}
