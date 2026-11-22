// PhoneCap <seconds> <out.mov> <log.txt>
// Records the USB-connected iPhone's screen, writing every frame with its capture timestamp.
import AVFoundation
import CoreMediaIO

let args = CommandLine.arguments
let seconds = Double(args.count > 1 ? args[1] : "5") ?? 5
let out = URL(fileURLWithPath: args.count > 2 ? args[2] : "phone.mov")
if args.count > 3 { freopen(args[3], "w", stdout) }
setbuf(stdout, nil)

var prop = CMIOObjectPropertyAddress(mSelector: CMIOObjectPropertySelector(kCMIOHardwarePropertyAllowScreenCaptureDevices), mScope: CMIOObjectPropertyScope(kCMIOObjectPropertyScopeGlobal), mElement: CMIOObjectPropertyElement(kCMIOObjectPropertyElementMain))
var allow: UInt32 = 1
CMIOObjectSetPropertyData(CMIOObjectID(kCMIOObjectSystemObject), &prop, 0, nil, UInt32(MemoryLayout<UInt32>.size), &allow)

var device: AVCaptureDevice?
let deadline = Date().addingTimeInterval(20)
while device == nil, Date() < deadline {
  device = AVCaptureDevice.DiscoverySession(deviceTypes: [.external], mediaType: .muxed, position: .unspecified).devices.first
  if device == nil { RunLoop.main.run(until: Date().addingTimeInterval(0.25)) }
}
guard let device else { print("ERROR phone screen not found (plugged in and unlocked?)"); exit(2) }
let sem = DispatchSemaphore(value: 0)
var granted = AVCaptureDevice.authorizationStatus(for: .video) == .authorized
if !granted { AVCaptureDevice.requestAccess(for: .video) { granted = $0; sem.signal() }; sem.wait() }
guard granted else { print("ERROR camera permission denied"); exit(3) }

final class Recorder: NSObject, AVCaptureVideoDataOutputSampleBufferDelegate {
  let url: URL
  var writer: AVAssetWriter?
  var input: AVAssetWriterInput?
  var start: CMTime?
  var stopAt: CMTime?
  var frames = 0
  var finished = false
  init(url: URL) { self.url = url }
  func captureOutput(_ output: AVCaptureOutput, didOutput sample: CMSampleBuffer, from connection: AVCaptureConnection) {
    guard !finished, let fmt = CMSampleBufferGetFormatDescription(sample) else { return }
    let pts = CMSampleBufferGetPresentationTimeStamp(sample)
    if writer == nil {
      let dims = CMVideoFormatDescriptionGetDimensions(fmt)
      try? FileManager.default.removeItem(at: url)
      let w = try! AVAssetWriter(outputURL: url, fileType: .mov)
      let i = AVAssetWriterInput(mediaType: .video, outputSettings: [
        AVVideoCodecKey: AVVideoCodecType.h264, AVVideoWidthKey: Int(dims.width), AVVideoHeightKey: Int(dims.height),
        AVVideoCompressionPropertiesKey: [AVVideoAverageBitRateKey: 20_000_000, AVVideoExpectedSourceFrameRateKey: 60],
      ])
      i.expectsMediaDataInRealTime = true
      w.add(i); w.startWriting(); w.startSession(atSourceTime: pts)
      writer = w; input = i; start = pts
      stopAt = CMTimeAdd(pts, CMTime(seconds: seconds, preferredTimescale: 600))
      print("START wall=\(Date().timeIntervalSince1970) host=\(pts.seconds) size=\(dims.width)x\(dims.height)")
    }
    if let stopAt, CMTimeCompare(pts, stopAt) >= 0 { finished = true; return }
    if input?.isReadyForMoreMediaData == true { input?.append(sample); frames += 1 }
    print("F \(String(format: "%.6f", (pts - start!).seconds))")
  }
}
let session = AVCaptureSession()
session.addInput(try! AVCaptureDeviceInput(device: device))
let output = AVCaptureVideoDataOutput()
output.alwaysDiscardsLateVideoFrames = false
let recorder = Recorder(url: out)
let queue = DispatchQueue(label: "cap")
output.setSampleBufferDelegate(recorder, queue: queue)
session.addOutput(output)
session.startRunning()
while !(queue.sync { recorder.finished }) {
  RunLoop.main.run(until: Date().addingTimeInterval(0.1))
  if Date() > deadline.addingTimeInterval(seconds + 30) { print("ERROR no frames"); exit(5) }
}
session.stopRunning()
let done = DispatchSemaphore(value: 0)
queue.sync {
  recorder.input?.markAsFinished()
  recorder.writer?.finishWriting { done.signal() }
}
done.wait()
print("SAVED \(out.path) frames=\(recorder.frames)")
