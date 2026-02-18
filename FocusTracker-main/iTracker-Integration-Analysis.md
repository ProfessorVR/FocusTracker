# iTracker Integration Analysis for FocusTracker

## Paper Overview

**Title:** Eye Tracking for Everyone
**Authors:** Kyle Krafka, Aditya Khosla, Petr Kellnhofer, Harini Kannan, Suchendra Bhandarkar, Wojciech Matusik, Antonio Torralba
**Venue:** CVPR 2016 (MIT CSAIL)
**Paper:** https://gazecapture.csail.mit.edu/cvpr2016_gazecapture.pdf
**Project site:** https://gazecapture.csail.mit.edu/
**Code:** https://github.com/CSAILVision/GazeCapture

---

## What iTracker Does

iTracker is a convolutional neural network that predicts where on a phone/tablet screen a user is looking, using only the front-facing camera. Unlike our current ARKit-based approach, it does **not** require a TrueDepth camera or face mesh -- it works from a standard RGB image alone.

### Architecture

iTracker takes four inputs extracted from each camera frame:

| Input | Size | Source |
|-------|------|--------|
| Left eye crop | 224x224 | Cropped from detected face |
| Right eye crop | 224x224 | Cropped from detected face |
| Face crop | 224x224 | Full face bounding box |
| Face grid | 25x25 | Binary mask encoding head position/size in frame |

Each image input passes through its own convolutional pathway:

```
Eye streams (shared weights):
  Conv 11x11/96 -> Conv 5x5/256 -> Conv 3x3/384 -> Conv 1x1/64 -> FC-128

Face stream:
  Conv 11x11/96 -> Conv 5x5/256 -> Conv 3x3/384 -> Conv 1x1/64 -> FC-128 -> FC-64

Face grid stream:
  FC-256 -> FC-128

All streams concatenate -> FC-128 -> FC-2 (x, y in cm)
```

The output is a 2D gaze point in centimeters relative to the camera, which is then converted to screen coordinates.

### Key Results

| Metric | Without Calibration | With Calibration (13-point SVR) |
|--------|--------------------|---------------------------------|
| iPhone error | **1.71 cm** (~2.4 degrees) | **1.34 cm** (~1.9 degrees) |
| iPad error | 2.53 cm | 2.12 cm |
| Speed | 10-15 FPS on mobile | Same |

### GazeCapture Dataset

- **1,474 subjects** across diverse demographics
- **2.5 million frames** total (1.49M with valid face/eye detections)
- Collected via a crowdsourced iOS app (users tap dots on screen)
- Includes: face crops, left/right eye crops, face grids, dot positions, device metadata, accelerometer/gyro data
- Available for download at https://gazecapture.csail.mit.edu/download.php

---

## Current FocusTracker Approach vs. iTracker

### What FocusTracker Does Now

FocusTracker uses **ARKit face tracking** with the TrueDepth camera:

1. `GazeTracker.swift` -- runs `ARFaceTrackingConfiguration`, extracts `lookAtPoint` from `ARFaceAnchor`
2. `ScreenMapper.swift` -- projects the 3D lookAtPoint onto a 2D screen plane using a geometric model (estimated phone distance of 35cm, hardcoded screen dimensions, ray-plane intersection)
3. `CalibrationEngine.swift` -- 5-point affine calibration (scale + offset + rotation) to correct systematic errors
4. `GazeSmoothing.swift` -- EMA temporal filter to reduce jitter

### Comparison

| Aspect | FocusTracker (Current) | iTracker (MIT) |
|--------|----------------------|----------------|
| **Sensor** | TrueDepth (depth + IR) | RGB camera only |
| **Device support** | iPhone X+ only | Any phone with front camera |
| **Approach** | Geometric projection (3D ray -> 2D plane) | Learned CNN regression |
| **Accuracy** | Unknown (depends heavily on assumed distance, screen dimensions, calibration) | 1.71cm / 1.34cm calibrated |
| **Calibration** | 5-point affine transform | 13-point SVR (support vector regression) |
| **Robustness** | Sensitive to distance/angle assumptions | Trained on 1,474 people in varied conditions |
| **Speed** | 30 FPS (native ARKit) | 10-15 FPS (CNN inference) |

---

## How iTracker Could Improve FocusTracker

### Option A: Replace ScreenMapper with iTracker CNN (Recommended)

**What changes:** Keep ARKit for face detection (bounding boxes, eye crops) but replace the geometric ScreenMapper with a CoreML model that predicts gaze point directly from image crops.

**Why this is the best option:**
- The geometric approach in `ScreenMapper.swift` relies on hardcoded assumptions (35cm phone distance, fixed screen dimensions in meters) that cause large errors when the user holds the phone at a different distance or angle
- iTracker learned the mapping from 2.5M real-world frames across 1,474 people -- it implicitly handles distance variation, head pose, and individual eye anatomy
- ARKit already gives us face/eye bounding boxes, so extracting the four iTracker inputs is straightforward
- CoreML runs on the Neural Engine (5 trillion ops/sec on modern iPhones), so inference would be fast

**Implementation path:**

```
1. Convert pretrained iTracker model -> CoreML (.mlpackage)
   - Source: Caffe weights from GazeCapture repo (itracker25x_iter_92000.caffemodel)
   - Tool: coremltools Python package
   - Output: iTracker.mlpackage (import into Xcode)

2. Create GazePredictionService.swift
   - Load CoreML model
   - Accept: ARFrame (camera image) + ARFaceAnchor (bounding boxes)
   - Crop: left eye (224x224), right eye (224x224), face (224x224)
   - Build: face grid (25x25 binary mask from face bbox)
   - Run: CoreML inference -> (x_cm, y_cm)
   - Convert: cm -> screen points using device specs

3. Modify GazeTracker.swift
   - In buildGazeFrame(), call GazePredictionService instead of ScreenMapper
   - Pass the ARFrame's capturedImage + faceAnchor bounding boxes
   - Output: predicted screen point replaces the geometric projection

4. Remove/deprecate ScreenMapper.swift
   - No longer needed for gaze point computation
   - Keep CalibrationEngine for optional personal calibration on top
```

**Estimated accuracy improvement:** From unknown (likely 3-5cm+ given the geometric assumptions) to ~1.7cm uncalibrated, ~1.3cm calibrated.

### Option B: Use GazeCapture Data to Train a Custom Model

**What changes:** Download the GazeCapture dataset, train a model optimized for our specific use case (iPhone-only, focus tracking, fixed portrait orientation).

**Advantages over Option A:**
- Can train on iPhone-only data (better accuracy than the mixed phone/tablet model)
- Can use a smaller/faster architecture since we only target modern iPhones
- Can add our own training data collected through the app
- Can optimize for CoreML/Neural Engine specifically

**Disadvantages:**
- Requires significant ML infrastructure (GPU training, data pipeline)
- The pretrained model is already quite good -- marginal gains for large effort
- Overkill for a prototype

**Recommendation:** Start with Option A (pretrained model), then consider Option B as a v2 improvement if the prototype is successful.

### Option C: Hybrid Approach -- ARKit + iTracker Ensemble

**What changes:** Run both the current ARKit geometric pipeline and iTracker CNN in parallel, fuse their outputs.

**How it works:**
- ARKit geometric projection provides a fast, smooth signal (30 FPS)
- iTracker CNN provides a more accurate but slower signal (10-15 FPS)
- Weighted average or Kalman filter fuses the two streams
- When CNN confidence is high, weight it more; fall back to ARKit between CNN frames

**Advantages:**
- Best of both: ARKit smoothness + CNN accuracy
- Graceful degradation (if CNN is slow, ARKit fills in)
- More robust than either alone

**Disadvantages:**
- More complex to implement
- Higher power consumption (running both pipelines)

### Option D: Upgrade Calibration Only (Minimal Change)

**What changes:** Replace the current 5-point affine calibration with iTracker's SVR-based personal calibration technique.

**How it works:**
- Keep the current ARKit + ScreenMapper pipeline entirely
- Replace `CalibrationEngine.swift` (least-squares affine) with an SVR that learns a non-linear correction
- Use 9-13 calibration points instead of 5
- Train a lightweight SVR on the calibration data to map raw gaze -> corrected gaze

**Advantages:**
- Minimal code change (only calibration engine)
- Non-linear correction handles the geometric model's systematic errors better than an affine transform
- SVR from Apple's Create ML or accelerate framework

**Disadvantages:**
- Still limited by the geometric ScreenMapper's fundamental inaccuracies
- Diminishing returns -- fixing calibration doesn't fix the root cause (bad geometric model)

---

## Recommended Implementation Plan

### Phase 1: CoreML Model Integration (Option A)

**Effort:** ~2-3 days

1. **Convert the model** (Python, one-time):
   ```python
   import coremltools as ct

   # Load Caffe model
   model = ct.converters.caffe.convert(
       ('itracker_deploy.prototxt', 'itracker25x_iter_92000.caffemodel'),
       image_input_names=['image_face', 'image_left', 'image_right'],
       is_bgr=True
   )
   model.save('iTracker.mlpackage')
   ```

2. **Add to Xcode project** -- drag iTracker.mlpackage into the project. Xcode auto-generates a Swift interface.

3. **Create `GazePredictionService.swift`**:
   - Input: `CVPixelBuffer` (camera frame) + face/eye bounding boxes from ARKit
   - Crop and resize face/eyes to 224x224
   - Generate 25x25 face grid from face bounding box position
   - Run CoreML prediction
   - Output: gaze point in cm, convert to screen coordinates

4. **Wire into `GazeTracker.swift`**:
   - Access `ARFrame.capturedImage` in the session delegate
   - Pass to GazePredictionService alongside face anchor data
   - Replace `screenMapper.map()` call with CNN prediction

5. **Test and compare** accuracy against the geometric approach.

### Phase 2: Improved Calibration (Option D)

**Effort:** ~1 day

1. Increase calibration points from 5 to 9 or 13
2. Replace least-squares affine with SVR using Apple's Accelerate framework or a lightweight ML model
3. Store calibration model in UserDefaults/files instead of just 6 affine parameters

### Phase 3: Hybrid Fusion (Option C, Optional)

**Effort:** ~2 days

1. Run ARKit geometric at 30 FPS for smooth tracking
2. Run iTracker CNN at 10-15 FPS for accuracy correction
3. Kalman filter fuses both streams
4. Result: smooth, accurate, robust gaze signal

---

## Key Risks and Considerations

| Risk | Mitigation |
|------|-----------|
| CoreML model too slow for real-time | Neural Engine handles this; iTracker runs 10-15 FPS even on 2016 hardware. Modern iPhones with A17/A18 chips will be faster. |
| Model file size too large | The Caffe model is ~100MB. Can quantize to 8-bit (~25MB) or use Apple's model compression tools. |
| Accuracy worse than paper claims | Paper results are averages across many users. Personal calibration (Phase 2) should recover accuracy for individual users. |
| Face/eye crop quality from ARKit | ARKit provides excellent face bounding boxes via ARFaceAnchor. Cropping from the camera frame is straightforward. |
| Privacy concerns | All inference is on-device via CoreML. No data leaves the phone. Same privacy model as current ARKit approach. |

---

## Summary

The current FocusTracker uses a **geometric projection** model (`ScreenMapper`) that relies on hardcoded physical assumptions about phone distance and screen dimensions. This is the primary source of tracking inaccuracy.

**The single highest-impact improvement is replacing ScreenMapper with the pretrained iTracker CoreML model** (Option A). This gives us a gaze predictor trained on 2.5M frames from 1,474 people, running on-device via the Neural Engine, with demonstrated accuracy of 1.71cm uncalibrated and 1.34cm with personal calibration.

The GazeCapture dataset itself could also serve as a long-term asset if we later want to train a custom model optimized specifically for FocusTracker's use case (iPhone-only, portrait mode, focus scoring).
