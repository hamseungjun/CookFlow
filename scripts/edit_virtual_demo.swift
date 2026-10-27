import Foundation
import AVFoundation
import QuartzCore
import AppKit

// Cut only explicitly listed waiting intervals from the actual voiced recording.
// Retain the original video/audio and label generated inputs throughout.
let args = CommandLine.arguments
guard args.count == 4 else { fatalError("input-video kept-ranges.json output-video") }
let source = AVURLAsset(url: URL(fileURLWithPath: args[1]))
let ranges = try JSONSerialization.jsonObject(with: Data(contentsOf: URL(fileURLWithPath: args[2]))) as! [[Double]]
let composition = AVMutableComposition()
let sourceVideo = source.tracks(withMediaType: .video)[0]
let video = composition.addMutableTrack(withMediaType: .video, preferredTrackID: kCMPersistentTrackID_Invalid)!
let audioPairs = source.tracks(withMediaType: .audio).map { ($0, composition.addMutableTrack(withMediaType: .audio, preferredTrackID: kCMPersistentTrackID_Invalid)!) }
var cursor = CMTime.zero
for bounds in ranges {
 let range = CMTimeRange(start: CMTime(seconds:bounds[0],preferredTimescale:600), duration:CMTime(seconds:bounds[1]-bounds[0],preferredTimescale:600))
 try video.insertTimeRange(range,of:sourceVideo,at:cursor)
 for (original, target) in audioPairs {
  let intersection = CMTimeRangeGetIntersection(range, otherRange: original.timeRange)
  if intersection.duration.seconds > 0 {
   try target.insertTimeRange(intersection,of:original,at:CMTimeAdd(cursor,CMTimeSubtract(intersection.start,range.start)))
  }
 }
 cursor = CMTimeAdd(cursor,range.duration)
}
let size = sourceVideo.naturalSize.applying(sourceVideo.preferredTransform)
let renderSize = CGSize(width:abs(size.width),height:abs(size.height))
let instruction = AVMutableVideoCompositionInstruction(); instruction.timeRange = CMTimeRange(start:.zero,duration:cursor)
let layerInstruction = AVMutableVideoCompositionLayerInstruction(assetTrack:video)
layerInstruction.setTransform(sourceVideo.preferredTransform,at:.zero); instruction.layerInstructions = [layerInstruction]
let visual = AVMutableVideoComposition(); visual.renderSize = renderSize; visual.frameDuration = CMTime(value:1,timescale:30); visual.instructions = [instruction]
let root = CALayer(); root.frame = CGRect(origin:.zero,size:renderSize)
let movie = CALayer(); movie.frame = root.bounds; root.addSublayer(movie)
let badge = CALayer(); badge.frame = CGRect(x:20,y:18,width:renderSize.width-40,height:48)
badge.backgroundColor = CGColor(gray:0,alpha:0.7); badge.cornerRadius = 12
let bitmap = NSBitmapImageRep(bitmapDataPlanes:nil,pixelsWide:Int(badge.bounds.width),pixelsHigh:48,bitsPerSample:8,samplesPerPixel:4,hasAlpha:true,isPlanar:false,colorSpaceName:.deviceRGB,bytesPerRow:0,bitsPerPixel:0)!
NSGraphicsContext.saveGraphicsState(); NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep:bitmap)
let paragraph = NSMutableParagraphStyle(); paragraph.alignment = .center
let caption = NSAttributedString(string:"가상 시연 · AI 생성 이미지 · 대기 구간 편집",attributes:[.font:NSFont.systemFont(ofSize:24,weight:.semibold),.foregroundColor:NSColor.white,.paragraphStyle:paragraph])
caption.draw(in:CGRect(x:0,y:8,width:badge.bounds.width,height:32))
NSGraphicsContext.restoreGraphicsState(); badge.contents = bitmap.cgImage
root.addSublayer(badge)
visual.animationTool = AVVideoCompositionCoreAnimationTool(postProcessingAsVideoLayer:movie,in:root)
let export = AVAssetExportSession(asset:composition,presetName:AVAssetExportPreset1920x1080)!
export.videoComposition = visual; export.outputURL = URL(fileURLWithPath:args[3]); export.outputFileType = .mp4; export.shouldOptimizeForNetworkUse = true
export.exportAsynchronously { if export.status == .completed { print("Edited actual demo: \(Int(cursor.seconds)) seconds"); exit(0) }; print(export.error?.localizedDescription ?? "Export failed"); exit(1) }
dispatchMain()
