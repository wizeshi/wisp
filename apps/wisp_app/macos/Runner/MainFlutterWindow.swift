import Cocoa
import FlutterMacOS
import YouTubeKit

class MainFlutterWindow: NSWindow {
  override func awakeFromNib() {
    let flutterViewController = FlutterViewController()
    let windowFrame = self.frame
    self.contentViewController = flutterViewController
    self.setFrame(windowFrame, display: true)

    RegisterGeneratedPlugins(registry: flutterViewController)
    setupYouTubeKitChannel(with: flutterViewController.engine.binaryMessenger)

    super.awakeFromNib()
  }

  private func setupYouTubeKitChannel(with messenger: FlutterBinaryMessenger) {
    let channel = FlutterMethodChannel(
      name: "dev.wizeshi.wisp/youtube",
      binaryMessenger: messenger
    )

    channel.setMethodCallHandler { [weak self] (call, result) in
      guard let self else { return }

      switch call.method {
      case "getStreamUrlYoutubeKit", "getStreamUrlYoutubeKitIOS":
        guard
          let args = call.arguments as? [String: Any],
          let videoId = args["videoId"] as? String
        else {
          result(FlutterError(
            code: "INVALID_ARGUMENTS",
            message: "Invalid arguments for \(call.method)",
            details: nil
          ))
          return
        }

        Task {
          do {
            let streamDetails = try await self.getStreamDetailsUsingYouTubeKit(videoId: videoId)
            result(streamDetails)
          } catch {
            result(FlutterError(
              code: "STREAM_FETCH_FAILED",
              message: error.localizedDescription,
              details: nil
            ))
          }
        }

      default:
        result(FlutterMethodNotImplemented)
      }
    }
  }

  private func getStreamDetailsUsingYouTubeKit(videoId: String) async throws -> [String: Any] {
    let video = YouTube(videoID: videoId, methods: [.local, .remote])

    // On macOS, media_kit / mpv can decode Opus/WebM and AAC/M4A natively.
    guard
      let audioStream = try await video.streams
        .filterAudioOnly()
        .highestAudioBitrateStream()
    else {
      throw NSError(
        domain: "dev.wizeshi.wisp.youtube",
        code: -1,
        userInfo: [NSLocalizedDescriptionKey: "No audio stream available for \(videoId)"]
      )
    }

    return [
      "url": audioStream.url.absoluteString,
      "format": audioStream.fileExtension.rawValue,
      "bitrate": audioStream.bitrate ?? 160000
    ]
  }
}
