import AVFoundation

/// TTS 服务（对齐原版音色预览 / hatch_voice_id 的本地实现）：
/// 音色枚举、选择、试听、播客播放（AVSpeechSynthesizer，逐句队列近似流式）。
@MainActor
final class TtsService: NSObject, ObservableObject, AVSpeechSynthesizerDelegate {
    static let shared = TtsService()

    private let synthesizer = AVSpeechSynthesizer()
    @Published var isSpeaking = false

    override init() {
        super.init()
        synthesizer.delegate = self
    }

    /// 可用音色（系统 TTS）
    var voices: [AVSpeechSynthesisVoice] {
        AVSpeechSynthesisVoice.speechVoices()
            .filter { $0.language.hasPrefix("zh") || $0.language.hasPrefix("en") }
            .sorted { $0.name < $1.name }
    }

    func setVoice(_ voice: AVSpeechSynthesisVoice) {
        UserDefaults.standard.set(voice.identifier, forKey: "muse.tts.voice")
    }

    func currentVoice() -> AVSpeechSynthesisVoice? {
        if let id = UserDefaults.standard.string(forKey: "muse.tts.voice") {
            return AVSpeechSynthesisVoice(identifier: id)
        }
        return AVSpeechSynthesisVoice(language: "zh-CN")
    }

    /// 试听（音色预览）
    func preview(_ voice: AVSpeechSynthesisVoice) {
        setVoice(voice)
        speak("你好，我是 Muse。这是当前音色的试听效果。")
    }

    /// 播放文本（播客剧集按句拆分入队，近似流式播放）
    func speak(_ text: String) {
        stop()
        let sentences = text.components(separatedBy: CharacterSet(charactersIn: "。\n"))
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
        for sentence in sentences {
            let utterance = AVSpeechUtterance(string: sentence + "。")
            utterance.voice = currentVoice()
            utterance.rate = 0.5
            synthesizer.speak(utterance)
        }
        isSpeaking = true
    }

    func stop() {
        synthesizer.stopSpeaking(at: .immediate)
        isSpeaking = false
    }

    func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didFinish utterance: AVSpeechUtterance) {
        isSpeaking = synthesizer.isSpeaking
    }
}
