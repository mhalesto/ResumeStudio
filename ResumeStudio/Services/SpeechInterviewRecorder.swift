import AVFoundation
import Foundation
import Speech

@MainActor
final class SpeechInterviewRecorder: ObservableObject {
  @Published private(set) var isRecording = false
  @Published private(set) var transcript = ""
  @Published private(set) var errorMessage: String?
  @Published private(set) var durationSeconds: Double = 0
  @Published private(set) var lastRecordingURL: URL?
  @Published private(set) var pauseCount = 0
  @Published private(set) var longestPauseSeconds: Double = 0

  private let audioEngine = AVAudioEngine()
  private var recognitionRequest: SFSpeechAudioBufferRecognitionRequest?
  private var recognitionTask: SFSpeechRecognitionTask?
  private var startedAt: Date?
  private var timer: Timer?
  private var audioFile: AVAudioFile?
  private var timeLimitSeconds: Double?

  func requestAccess() async -> Bool {
    let speechStatus = await withCheckedContinuation { continuation in
      SFSpeechRecognizer.requestAuthorization { continuation.resume(returning: $0) }
    }
    guard speechStatus == .authorized else {
      errorMessage = "Speech recognition permission is required for voice practice."
      return false
    }
    let microphoneAllowed = await AVAudioApplication.requestRecordPermission()
    if !microphoneAllowed { errorMessage = "Microphone permission is required for voice practice." }
    return microphoneAllowed
  }

  func start(timeLimitSeconds: Double? = nil) async {
    guard await requestAccess() else { return }
    stop()
    transcript = ""
    lastRecordingURL = nil
    errorMessage = nil
    pauseCount = 0
    longestPauseSeconds = 0
    self.timeLimitSeconds = timeLimitSeconds

    guard let recognizer = SFSpeechRecognizer(), recognizer.isAvailable else {
      errorMessage = "Speech recognition is currently unavailable."
      return
    }

    do {
      let session = AVAudioSession.sharedInstance()
      try session.setCategory(.record, mode: .measurement, options: .duckOthers)
      try session.setActive(true, options: .notifyOthersOnDeactivation)

      let request = SFSpeechAudioBufferRecognitionRequest()
      request.shouldReportPartialResults = true
      if recognizer.supportsOnDeviceRecognition { request.requiresOnDeviceRecognition = true }
      recognitionRequest = request

      recognitionTask = recognizer.recognitionTask(with: request) { [weak self] result, error in
        Task { @MainActor in
          if let result {
            self?.transcript = result.bestTranscription.formattedString
            self?.updatePauseMetrics(result.bestTranscription.segments)
          }
          if error != nil || result?.isFinal == true { self?.stop() }
        }
      }

      let input = audioEngine.inputNode
      let format = input.outputFormat(forBus: 0)
      let root = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        .appendingPathComponent("ResumeStudio/VoicePractice", isDirectory: true)
      try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
      let recordingURL = root.appendingPathComponent("\(UUID().uuidString).caf")
      let outputFile = try AVAudioFile(forWriting: recordingURL, settings: format.settings)
      audioFile = outputFile
      lastRecordingURL = recordingURL
      input.installTap(onBus: 0, bufferSize: 1_024, format: format) { buffer, _ in
        request.append(buffer)
        try? outputFile.write(from: buffer)
      }
      audioEngine.prepare()
      try audioEngine.start()
      startedAt = Date()
      durationSeconds = 0
      isRecording = true
      timer = Timer.scheduledTimer(withTimeInterval: 0.25, repeats: true) { [weak self] _ in
        Task { @MainActor in
          guard let start = self?.startedAt else { return }
          self?.durationSeconds = Date().timeIntervalSince(start)
          if let limit = self?.timeLimitSeconds, self?.durationSeconds ?? 0 >= limit {
            self?.stop()
          }
        }
      }
    } catch {
      errorMessage = error.localizedDescription
      stop()
    }
  }

  func stop() {
    if audioEngine.isRunning {
      audioEngine.stop()
      audioEngine.inputNode.removeTap(onBus: 0)
    }
    recognitionRequest?.endAudio()
    recognitionTask?.cancel()
    recognitionTask = nil
    recognitionRequest = nil
    audioFile = nil
    timer?.invalidate()
    timer = nil
    if let startedAt { durationSeconds = max(durationSeconds, Date().timeIntervalSince(startedAt)) }
    startedAt = nil
    timeLimitSeconds = nil
    isRecording = false
    try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
  }

  func replaceTranscript(_ value: String) { transcript = value }

  private func updatePauseMetrics(_ segments: [SFTranscriptionSegment]) {
    guard segments.count > 1 else { pauseCount = 0; longestPauseSeconds = 0; return }
    let gaps = zip(segments, segments.dropFirst()).map { current, next in
      max(0, next.timestamp - (current.timestamp + current.duration))
    }
    pauseCount = gaps.count { $0 >= 0.8 }
    longestPauseSeconds = gaps.max() ?? 0
  }
}

@MainActor
final class AudioPreviewPlayer: NSObject, ObservableObject, AVAudioPlayerDelegate {
  @Published private(set) var isPlaying = false
  private var player: AVAudioPlayer?

  func toggle(url: URL) {
    if isPlaying { player?.stop(); isPlaying = false; return }
    do {
      player = try AVAudioPlayer(contentsOf: url)
      player?.delegate = self
      player?.play()
      isPlaying = true
    } catch { isPlaying = false }
  }

  nonisolated func audioPlayerDidFinishPlaying(_ player: AVAudioPlayer, successfully flag: Bool) {
    Task { @MainActor in self.isPlaying = false }
  }
}
