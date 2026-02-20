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

import numpy as np


def expand_facegrid_input(model, old_size=625, new_size=628):
    """Expand the facegrid input from 625 to 628 elements.

    The original iTracker uses a 25x25 binary face grid (625 elements).
    We extend it with 3 normalized Euler angles (pitch, yaw, roll) at
    indices 625-627. The first FC layer connected to the facegrid input
    is padded with 3 zero columns so the model produces identical output
    until fine-tuned on data that includes head orientation.

    Args:
        model: A coremltools NeuralNetwork model spec.
        old_size: Original facegrid dimension (625).
        new_size: New facegrid dimension (628).

    Returns:
        The modified model spec with expanded facegrid input.
    """
    spec = model.get_spec()

    # Update the facegrid input shape.
    for inp in spec.description.input:
        if inp.name == "facegrid":
            # MultiArray input shape
            if inp.type.HasField("multiArrayType"):
                dims = inp.type.multiArrayType.shape
                for i, d in enumerate(dims):
                    if d == old_size:
                        dims[i] = new_size
                        print(f"  Updated facegrid input shape: {old_size} -> {new_size}")
                        break

    # Find and pad the first FC layer connected to facegrid.
    nn = spec.neuralNetwork
    for layer in nn.layers:
        if layer.WhichOneof("layer") == "innerProduct":
            # Check if this layer's input connects to the facegrid path.
            if any("facegrid" in inp.lower() or "grid" in inp.lower()
                   for inp in layer.input):
                ip = layer.innerProduct
                old_input_channels = ip.inputChannels
                if old_input_channels == old_size:
                    ip.inputChannels = new_size
                    # Reshape weights: [outputChannels x inputChannels]
                    weights = np.array(ip.weights.floatValue)
                    output_channels = ip.outputChannels
                    weight_matrix = weights.reshape(output_channels, old_size)
                    # Pad with 3 zero columns (new Euler angle connections).
                    padding = np.zeros((output_channels, new_size - old_size),
                                       dtype=np.float32)
                    expanded = np.concatenate([weight_matrix, padding], axis=1)
                    del ip.weights.floatValue[:]
                    ip.weights.floatValue.extend(expanded.flatten().tolist())
                    print(f"  Padded FC layer weights: "
                          f"{old_size} -> {new_size} input channels "
                          f"({output_channels} outputs)")
                    break

    import coremltools as ct
    return ct.models.MLModel(spec)


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

    # Expand facegrid from 625 to 628 (add 3 Euler angle inputs).
    print("\nExpanding facegrid input from 625 to 628 (+ pitch, yaw, roll)...")
    model = expand_facegrid_input(model, old_size=625, new_size=628)

    # Update model metadata
    model.author = "MIT CSAIL (converted for FocusTracker)"
    model.short_description = (
        "iTracker CNN for gaze prediction. Inputs: face crop (224x224), "
        "left eye crop (224x224), right eye crop (224x224), face grid (628: "
        "25x25 binary grid + 3 normalized Euler angles). "
        "Output: gaze residual in centimeters (dx, dy) relative to camera."
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
