import Flutter
import UIKit
import YouTubeKit

@main
@objc class AppDelegate: FlutterAppDelegate, FlutterImplicitEngineDelegate {

  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    // Do NOT touch window?.rootViewController here — with the implicit-engine
    // lifecycle it may not exist yet. Channel setup happens in
    // didInitializeImplicitFlutterEngine below instead.
    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }

  func didInitializeImplicitFlutterEngine(_ engineBridge: FlutterImplicitEngineBridge) {
    GeneratedPluginRegistrant.register(with: engineBridge.pluginRegistry)

    let platformChannel = FlutterMethodChannel(
      name: "dev.wizeshi.wisp/youtube",
      binaryMessenger: engineBridge.applicationRegistrar.messenger()
    )

    platformChannel.setMethodCallHandler { [weak self] (call, result) in
      guard let self else { return }

      switch call.method {
      case "getStreamUrlYoutubeKitIOS":
        guard
          let args = call.arguments as? [String: Any],
          let videoId = args["videoId"] as? String
        else {
          result(FlutterError(
            code: "INVALID_ARGUMENTS",
            message: "Invalid arguments for getStreamUrlYoutubeKitIOS",
            details: nil
          ))
          return
        }

        // setMethodCallHandler's closure is synchronous, so the async
        // YouTubeKit call needs to run in a Task; `result` is called
        // once that finishes.
        Task {
          do {
            let streamUrl = try await self.getStreamUrlUsingYouTubeKit(videoId: videoId)
            result(streamUrl)
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

  private func getStreamUrlUsingYouTubeKit(videoId: String) async throws -> String {
    let video = YouTube(videoID: videoId, methods: [.local, .remote])

    // AVPlayer can only decode M4A/AAC audio containers — it cannot open
    // WebM/Opus, which is frequently what YouTube serves as the raw
    // highest-bitrate audio-only stream. Filtering to .m4a first (as
    // YouTubeKit's own docs demonstrate) avoids handing AVPlayer a format
    // it will reject outright with AVFoundationErrorDomain -11828
    // ("Cannot Open").
    guard
      let audioStream = try await video.streams
        .filterAudioOnly()
        .filter({ $0.fileExtension == .m4a })
        .highestAudioBitrateStream()
    else {
      throw NSError(
        domain: "dev.wizeshi.wisp.youtube",
        code: -1,
        userInfo: [NSLocalizedDescriptionKey: "No m4a audio-only stream available for \(videoId)"]
      )
    }

    return audioStream.url.absoluteString
  }
}