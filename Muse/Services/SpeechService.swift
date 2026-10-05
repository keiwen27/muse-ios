import AVFoundation
import Speech

/// 语音服务：按住说话录音（AAC，实时电平）+ 设备端转写（SFSpeechRecognizer）
/// 主线程隔离：AVAudioRecorder 的电平 Timer 依赖主线程 RunLoop
@MainActor
final class SpeechService: NSObject {
    var onLevel: ((Double) -> Void)?
    private(set) var isRecording = false
    private var recorder: AVAudioRecorder?
    private var meterTimer: Timer?

    /// 请求麦克风权限；返回是否已授权
    func requestMicPermission() async -> Bool {
        await withCheckedContinuation { cont in
            AVAudioSession.sharedInstance().requestRecordPermission { granted in
                cont.resume(returning: granted)
            }
        }
    }

    func start() async throws {
        let session = AVAudioSession.sharedInstance()
        try session.setCategory(.playAndRecord, mode: .default, options: [.defaultToSpeaker, .allowBluetooth])
        try session.setActive(true)
        guard await requestMicPermission() else {
            throw NSError(domain: "MuseVoice", code: 1,
                          userInfo: [NSLocalizedDescriptionKey: "语音输入需要访问麦克风（设置 → Muse → 麦克风）"])
        }

        let url = Self.voicesDirectory
            .appendingPathComponent("voice-\(Int(Date().timeIntervalSince1970)).m4a")
        let settings: [String: Any] = [
            AVFormatIDKey: kAudioFormatMPEG4AAC,
            AVSampleRateKey: 16_000,
            AVNumberOfChannelsKey: 1,
            AVEncoderAudioQualityKey: AVAudioQuality.medium.rawValue,
        ]
        let rec = try AVAudioRecorder(url: url, settings: settings)
        rec.isMeteringEnabled = true
        rec.record()
        recorder = rec
        isRecording = true

        meterTimer = Timer.scheduledTimer(withTimeInterval: 0.05, repeats: true) { [weak self] _ in
            guard let self, let r = self.recorder, r.isRecording else { return }
            r.updateMeters()
            let db = r.averagePower(forChannel: 0)            // -160...0
            self.onLevel?(Double(max(0, min(1, (db + 60) / 60))))
        }
    }

    /// 停止录音；时长 < 0.4s 视为误触，返回 nil
    func stop() -> URL? {
        meterTimer?.invalidate()
        meterTimer = nil
        guard let rec = recorder, isRecording else { return nil }
        let duration = rec.currentTime
        rec.stop()
        isRecording = false
        onLevel?(0)
        recorder = nil
        if duration < 0.4 { return nil }
        return rec.url
    }

    /// 设备端语音转写（iOS 15 可用）。未授权或失败返回 nil。
    func transcribe(url: URL) async -> String? {
        let status = await withCheckedContinuation { (cont: CheckedContinuation<SFSpeechRecognizerAuthorizationStatus, Never>) in
            SFSpeechRecognizer.requestAuthorization { cont.resume(returning: $0) }
        }
        guard status == .authorized, let recognizer = SFSpeechRecognizer() else { return nil }

        return await withCheckedContinuation { cont in
            guard let request = try? SFSpeechURLRecognitionRequest(contentsOf: url) else {
                cont.resume(returning: nil)
                return
            }
            request.shouldReportPartialResults = false

            var best = ""
            var finished = false
            recognizer.recognitionTask(with: request) { result, error in
                guard !finished else { return }
                if let text = result?.bestTranscription.formattedString, !text.isEmpty {
                    best = text
                }
                if result?.isFinal == true || error != nil {
                    finished = true
                    cont.resume(returning: best.isEmpty ? nil : best)
                }
            }
        }
    }

    static var voicesDirectory: URL {
        let dir = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Voices", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }
}
