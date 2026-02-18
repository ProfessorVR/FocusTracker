#!/usr/bin/env python3
"""
Convert the pretrained iTracker Caffe model to CoreML format.

Usage:
    1. Download the model from https://gazecapture.csail.mit.edu/
       - You need: itracker_deploy.prototxt and itracker25x_iter_92000.caffemodel
       - Place them in this directory (Scripts/)

    2. Install dependencies:
       pip install coremltools

    3. Run this script:
       python convert_itracker.py

    4. Copy the output iTracker.mlpackage into the Xcode project:
       - Drag iTracker.mlpackage into FocusTracker/ in Xcode
       - Xcode will compile it to .mlmodelc automatically

Requirements:
    - Python 3.8+
    - coremltools >= 7.0
    - macOS (for full CoreML validation)

Reference:
    Krafka et al., "Eye Tracking for Everyone," CVPR 2016
    https://gazecapture.csail.mit.edu/
"""

import os
import sys

def main():
    try:
        import coremltools as ct
        print(f"coremltools version: {ct.__version__}")
    except ImportError:
        print("ERROR: coremltools not installed. Run: pip install coremltools")
        sys.exit(1)

    script_dir = os.path.dirname(os.path.abspath(__file__))
    prototxt = os.path.join(script_dir, "itracker_deploy.prototxt")
    caffemodel = os.path.join(script_dir, "itracker25x_iter_92000.caffemodel")

    # Check for model files
    if not os.path.exists(prototxt):
        print(f"ERROR: {prototxt} not found.")
        print("Download from https://gazecapture.csail.mit.edu/")
        sys.exit(1)

    if not os.path.exists(caffemodel):
        print(f"ERROR: {caffemodel} not found.")
        print("Download from https://gazecapture.csail.mit.edu/")
        sys.exit(1)

    print("Converting iTracker Caffe model to CoreML...")
    print(f"  Prototxt:   {prototxt}")
    print(f"  Caffemodel: {caffemodel}")

    # Convert from Caffe to CoreML
    model = ct.converters.caffe.convert(
        (prototxt, caffemodel),
        image_input_names=["image_face", "image_left", "image_right"],
        is_bgr=True,
    )

    # Update model metadata
    model.author = "MIT CSAIL (converted for FocusTracker)"
    model.short_description = (
        "iTracker CNN for gaze prediction. Inputs: face crop (224x224), "
        "left eye crop (224x224), right eye crop (224x224), face grid (25x25). "
        "Output: gaze point in centimeters (x, y) relative to camera."
    )
    model.license = "Research use (GazeCapture dataset license)"

    # Save as .mlpackage (modern format, supports quantization)
    output_path = os.path.join(script_dir, "iTracker.mlpackage")
    model.save(output_path)
    print(f"\nModel saved to: {output_path}")

    # Optionally quantize to reduce size (~100MB -> ~25MB)
    print("\nQuantizing to 8-bit (reduces model size ~4x)...")
    try:
        quantized = ct.models.neural_network.quantization_utils.quantize_weights(
            model, nbits=8
        )
        quantized_path = os.path.join(script_dir, "iTracker_quantized.mlpackage")
        quantized.save(quantized_path)
        print(f"Quantized model saved to: {quantized_path}")
        print("\nRecommendation: Use the quantized model for smaller app size.")
        print("Both models should produce similar accuracy.")
    except Exception as e:
        print(f"Quantization failed (non-critical): {e}")
        print("Use the full-precision model instead.")

    print("\nNext steps:")
    print("  1. Open FocusTracker.xcodeproj in Xcode")
    print("  2. Drag iTracker.mlpackage (or iTracker_quantized.mlpackage) into the FocusTracker group")
    print("  3. Rename to 'iTracker.mlpackage' if using the quantized version")
    print("  4. Build and run — GazePredictionService will auto-detect the model")


if __name__ == "__main__":
    main()
