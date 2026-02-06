import Foundation

@MainActor
class OpenClawBridge: ObservableObject {
  @Published var lastToolCallStatus: ToolCallStatus = .idle

  private let urlSession: URLSession

  init() {
    let config = URLSessionConfiguration.default
    config.timeoutIntervalForRequest = 30
    self.urlSession = URLSession(configuration: config)
  }

  // MARK: - Webhook (async, for delegate_task / send_message)

  func delegateTask(
    task: String,
    deliver: Bool = false,
    channel: String? = nil,
    timeoutSeconds: Int = 120
  ) async -> ToolResult {
    lastToolCallStatus = .executing("delegate_task")

    guard let url = URL(string: "\(GeminiConfig.openClawHost):\(GeminiConfig.openClawPort)/hooks/agent") else {
      lastToolCallStatus = .failed("delegate_task", "Invalid URL")
      return .failure("Invalid gateway URL")
    }

    var request = URLRequest(url: url)
    request.httpMethod = "POST"
    request.setValue("Bearer \(GeminiConfig.openClawHookToken)", forHTTPHeaderField: "Authorization")
    request.setValue("application/json", forHTTPHeaderField: "Content-Type")

    var body: [String: Any] = [
      "message": task,
      "name": "Glass Voice",
      "sessionKey": "glass:default",
      "wakeMode": "now",
      "deliver": deliver,
      "timeoutSeconds": timeoutSeconds
    ]
    if let channel {
      body["channel"] = channel
    }

    do {
      request.httpBody = try JSONSerialization.data(withJSONObject: body)
      let (data, response) = try await urlSession.data(for: request)
      let httpResponse = response as? HTTPURLResponse

      if httpResponse?.statusCode == 202 {
        if let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
           let runId = json["runId"] as? String {
          NSLog("[OpenClaw] Task delegated (runId: %@)", runId)
          lastToolCallStatus = .completed("delegate_task")
          return .success("Task delegated (runId: \(runId))")
        }
        lastToolCallStatus = .completed("delegate_task")
        return .success("Task delegated successfully")
      } else {
        let statusCode = httpResponse?.statusCode ?? 0
        let bodyStr = String(data: data, encoding: .utf8) ?? "no body"
        NSLog("[OpenClaw] Webhook failed: HTTP %d - %@", statusCode, bodyStr)
        lastToolCallStatus = .failed("delegate_task", "HTTP \(statusCode)")
        return .failure("Gateway returned HTTP \(statusCode): \(bodyStr)")
      }
    } catch {
      NSLog("[OpenClaw] Webhook error: %@", error.localizedDescription)
      lastToolCallStatus = .failed("delegate_task", error.localizedDescription)
      return .failure("Gateway unreachable: \(error.localizedDescription)")
    }
  }

  // MARK: - Tool Invoke (synchronous, for web_search)

  func invokeTool(
    tool: String,
    action: String = "json",
    args: [String: Any]
  ) async -> ToolResult {
    lastToolCallStatus = .executing(tool)

    guard let url = URL(string: "\(GeminiConfig.openClawHost):\(GeminiConfig.openClawPort)/tools/invoke") else {
      lastToolCallStatus = .failed(tool, "Invalid URL")
      return .failure("Invalid gateway URL")
    }

    var request = URLRequest(url: url)
    request.httpMethod = "POST"
    request.setValue("Bearer \(GeminiConfig.openClawGatewayToken)", forHTTPHeaderField: "Authorization")
    request.setValue("application/json", forHTTPHeaderField: "Content-Type")

    let body: [String: Any] = [
      "tool": tool,
      "action": action,
      "args": args,
      "sessionKey": "glass:default"
    ]

    do {
      request.httpBody = try JSONSerialization.data(withJSONObject: body)
      let (data, response) = try await urlSession.data(for: request)
      let httpResponse = response as? HTTPURLResponse

      guard let statusCode = httpResponse?.statusCode, (200...299).contains(statusCode) else {
        let code = httpResponse?.statusCode ?? 0
        NSLog("[OpenClaw] Tool invoke failed: HTTP %d", code)
        lastToolCallStatus = .failed(tool, "HTTP \(code)")
        return .failure("Tool invoke failed: HTTP \(code)")
      }

      if let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
        if let error = json["error"] as? String {
          lastToolCallStatus = .failed(tool, error)
          return .failure(error)
        }
        let resultObj = json["result"] ?? json
        let resultData = try JSONSerialization.data(withJSONObject: resultObj, options: [.sortedKeys])
        let resultStr = String(data: resultData, encoding: .utf8) ?? "OK"
        NSLog("[OpenClaw] Tool %@ result: %@", tool, String(resultStr.prefix(200)))
        lastToolCallStatus = .completed(tool)
        return .success(resultStr)
      }

      lastToolCallStatus = .completed(tool)
      return .success(String(data: data, encoding: .utf8) ?? "OK")
    } catch {
      NSLog("[OpenClaw] Tool invoke error: %@", error.localizedDescription)
      lastToolCallStatus = .failed(tool, error.localizedDescription)
      return .failure("Tool invoke failed: \(error.localizedDescription)")
    }
  }
}
