import AVFoundation

/// Keeps fast movers sharp. At 60 fps auto-exposure may expose up to 1/60 s, which smears a rider passing at
/// 30 km/h across ~15 model pixels and costs the detector its confidence; capped at 1/120 s the smear halves,
/// at the price of a darker, noisier picture at night.
enum MotionBlur {
    static let maxExposure = CMTime(value: 1, timescale: 120)

    /// The cap for this format, inside what it supports.
    static func cap(for format: AVCaptureDevice.Format) -> CMTime {
        CMTimeClampToRange(maxExposure, range: CMTimeRange(start: format.minExposureDuration, end: format.maxExposureDuration))
    }

    /// Applies the cap to a device someone else (ARKit) configured. Call with the device unlocked.
    static func limit(_ device: AVCaptureDevice) {
        guard (try? device.lockForConfiguration()) != nil else { return }
        let cap = cap(for: device.activeFormat)
        if device.activeMaxExposureDuration != cap { device.activeMaxExposureDuration = cap }
        device.unlockForConfiguration()
    }
}
