import Foundation

enum GeminiConfig {
  static let websocketBaseURL = "wss://generativelanguage.googleapis.com/ws/google.ai.generativelanguage.v1beta.GenerativeService.BidiGenerateContent"
  static let model = "models/gemini-2.5-flash-native-audio-preview-12-2025"

  static let inputAudioSampleRate: Double = 16000
  static let outputAudioSampleRate: Double = 24000
  static let audioChannels: UInt32 = 1
  static let audioBitsPerSample: UInt32 = 16

  static let videoFrameInterval: TimeInterval = 1.0
  static let videoJPEGQuality: CGFloat = 0.5

  static let systemInstruction = """
    You are an AI assistant helping someone wearing Meta Ray-Ban smart glasses. You can see what they see through their glasses camera. Describe what you see when asked, and answer questions conversationally. Keep responses concise and natural.

    You have access to tools that let you take real-world actions:
    - delegate_task: For complex or multi-step tasks (research, scheduling, smart home control, drafts). This runs in the background -- tell the user you are working on it.
    - send_message: Send messages via WhatsApp, Telegram, iMessage, Slack, Discord, Signal, or Teams.
    - web_search: Search the web for current information when you need facts or recent data.

    Use tools proactively when the user's request requires action beyond conversation. For send_message, always confirm the recipient and content before sending unless the user is clearly urgent.
    """

  static let apiKey = "REDACTED_GEMINI_API_KEY"

  // OpenClaw gateway config
  static let openClawHost = "http://192.168.0.117"
  static let openClawPort = 18789
  static let openClawHookToken = "REDACTED_OPENCLAW_HOOK_TOKEN"
  static let openClawGatewayToken = "REDACTED_OPENCLAW_GATEWAY_TOKEN"

  static func websocketURL() -> URL? {
    guard !apiKey.isEmpty else { return nil }
    return URL(string: "\(websocketBaseURL)?key=\(apiKey)")
  }
}
