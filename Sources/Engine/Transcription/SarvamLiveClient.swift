// Copyright 2026 Adhish Thite
// SPDX-License-Identifier: Apache-2.0

import AVFoundation
import AppKit
import AudioToolbox
import Carbon
import CoreAudio
import Foundation
import IOKit
import Network
import SQLite3

/// Streaming transcription over Sarvam's realtime speech-to-text socket
/// (`/speech-to-text-realtime/ws`). One socket serves many turns: each turn is bracketed by
/// `speech_start` and `speech_end` (manual endpointing, because the shortcut owns the speech
/// boundary), and the server answers each bracket with `transcript.partial` events and one
/// or more `transcript.final` events.
final class SarvamLiveClient: NSObject, URLSessionWebSocketDelegate {
  let apiKey: String
  private let model: String
  var webSocketTask: URLSessionWebSocketTask?
  var urlSession: URLSession!

  let lock = NSLock()
  private var connectedState = false
  var readyState = false
  var connectionID: UInt64 = 0
  var turnID: UInt64 = 0
  var turnOpen = false
  var turnHasAudioGap = false
  private var reconnectEnabled = true
  let sendQueue = DispatchQueue(label: "com.adhishthite.stok.send", qos: .userInitiated)
  private var turnWrites = DispatchGroup()

  var pendingWrites: [PendingWrite] = []
  private var pendingWriteBytes = 0
  private var nextWriteID: UInt64 = 0
  var writeTransport: (URLSessionWebSocketTask, String, @escaping (Error?) -> Void) -> Void = {
    task, text, completion in
    task.send(.string(text), completionHandler: completion)
  }
  private var writeInFlight = false
  private var turnSentAnyMessage = false
  var writeDeadline: DispatchWorkItem?
  private static let maxPendingWriteBytes = 256 * 1024
  private static let maxPendingWriteAge = 3.0
  private var sessionEstablishedAt: TimeInterval = 0
  /// Why the in-flight connect attempt was started (startup, reconnect, wake). Read back
  /// once the session begins so the single "session ready" line can name it.
  var pendingConnectReason = "startup"
  var isConnected: Bool {
    lock.lock()
    defer { lock.unlock() }
    return connectedState
  }
  var isReady: Bool {
    lock.lock()
    defer { lock.unlock() }
    return readyState
  }
  /// Connection readiness and session age at the instant of a key-down: "ready" with the
  /// socket's age when a session is established, "connecting" while a handshake is in
  /// flight, "closed" otherwise. A brief lock scope; callers on main must never do more.
  var socketStateAtKeydown: (state: String, ageMs: Double?) {
    lock.lock()
    defer { lock.unlock() }
    if readyState {
      return ("ready", (ProcessInfo.processInfo.systemUptime - sessionEstablishedAt) * 1000.0)
    }
    return (webSocketTask != nil ? "connecting" : "closed", nil)
  }
  // Whether the socket identity changed (a new connection was established) or was lost
  // while the current turn was open. Reset in startNewTurn; set in connect() and
  // connectionFailed(), both already under `lock`. Read via lastConnectionChangedDuringTurn
  // after settle, the same pattern as lastSettlePath.
  private var turnConnectionChanged = false
  var lastConnectionChangedDuringTurn: Bool {
    lock.lock()
    defer { lock.unlock() }
    return turnConnectionChanged
  }
  // Round-trip split from commit to each network milestone the turn passes, all ms. Each is
  // set at most once per turn, at the moment the event lands, under `lock`; startNewTurn
  // resets them. Read via lastRoundTrip after settle, the same pattern as lastSettlePath.
  private var commitToLastSendMs: Double?
  private var commitToFirstMsgMs: Double?
  private var commitToFinalMs: Double?
  private var commitToTurnCompleteMs: Double?
  var lastRoundTrip:
    (lastSendMs: Double?, firstMsgMs: Double?, finalMs: Double?, turnCompleteMs: Double?)
  {
    lock.lock()
    defer { lock.unlock() }
    return (commitToLastSendMs, commitToFirstMsgMs, commitToFinalMs, commitToTurnCompleteMs)
  }
  var canCommitTurn: Bool {
    lock.lock()
    defer { lock.unlock() }
    return readyState && turnOpen && !turnHasAudioGap
  }

  var currentTurnText: String = ""
  // Multi-segment transcript accumulator. The server finalizes long speech in segments
  // (about every 18 to 20 seconds of audio, even with manual endpointing), each with its own
  // utterance index, and each final covers only its own audio. Finals are therefore kept by
  // index (`indexedFinals`), never merged by text: "Yes." twice is two answers. The text
  // accumulator `committedTranscript` is only a fallback for a final that carries no index.
  // `interimTranscript` is the in-progress segment (`interimIndex`); currentTurnText is
  // always the merge.
  var indexedFinals: [Int: String] = [:]
  var committedTranscript: String = ""
  var interimTranscript: String = ""
  var interimIndex: Int?
  private var firstTokenLatencyMs: Double = 0
  var turnCommitTime: CFAbsoluteTime = 0
  // When the turn's audio window opened, which is also when speech_start goes out.
  // firstTokenLatencyMs is measured from COMMIT and stays 0 whenever text arrived during the
  // hold, so it cannot answer how fast the service started transcribing.
  private var turnStartTime: CFAbsoluteTime = 0
  private var firstInterimLatencyMs: Double = 0
  private var completedFirstInterimMs: Double?
  private var lastTokenReceivedTime: CFAbsoluteTime = 0

  // Utterance bookkeeping. Indices count up across the whole session, one or more per turn.
  // Events for an utterance that already has its final are ignored, whatever order they
  // arrive in: indices below `utteranceFloor` belong to turns already settled on their
  // terminal final, and `finalizedUtterances` holds finalized indices at or above it, so the
  // set never outgrows one turn. The two turn fields tell whether the server split this turn
  // into several segments. All under `lock`.
  var finalizedUtterances = Set<Int>()
  private var utteranceFloor = 0
  private var turnTerminalUtteranceIdx: Int?
  private var turnFirstUtteranceIdx: Int?
  private var turnMaxUtteranceIdx: Int?

  // Audio accounting for the terminal-final decision, in PCM bytes acknowledged by the
  // socket. With return_timestamps the server stamps each final with `end_s`, the seconds of
  // session audio it covers; verified 2026-10-07 that the final answering speech_end ends at
  // exactly the session audio sent through that speech_end, while an earlier segment's final
  // ends sooner. All under `lock`.
  private var sessionAudioBytes = 0
  private var turnAudioBytes = 0
  private var turnEndAudioBytes: Int?
  /// Slack for float rounding in `end_s` (seen: 46.109 for 46.11 s sent).
  static let finalEndToleranceSeconds = 0.1
  /// Without timestamps, a turn this long may have been split by the server (segments were
  /// 18 to 20 s in checks), so its first final after speech_end is not trusted as the last.
  static let unsplitTurnMaxSeconds = 15.0

  /// Milliseconds from turn start to the first transcript text of any kind, or nil when the
  /// service sent none. Read after the turn completes.
  var lastTurnFirstInterimMs: Double? {
    lock.lock()
    defer { lock.unlock() }
    if hasFiredTurnCompletion { return completedFirstInterimMs }
    return firstInterimLatencyMs > 0 ? firstInterimLatencyMs : nil
  }

  // Which settlement rule ended the last turn, recorded per turn in history. Under `lock`;
  // read via lastSettlePath after completion.
  private var settlePathValue: String?
  var lastSettlePath: String? {
    lock.lock()
    defer { lock.unlock() }
    return settlePathValue
  }
  var commitWritesComplete = false
  var commitWritesCompletedAt: Double = 0
  private var serverCompletionReceived = false
  var isCommitting: Bool = false
  var hasFiredTurnCompletion: Bool = false
  var turnCompletion:
    ((Result<(text: String, firstTokenMs: Double, totalMs: Double), Error>) -> Void)?
  var onLiveTextUpdate: ((String) -> Void)?
  /// Called once when consecutive key rejections stop the reconnect loop.
  var onAuthRejected: (() -> Void)?
  /// Connection lifecycle telemetry: fired for a connect attempt, a lost
  /// connection, or an explicit close. Never called under `lock`. The receiver (History,
  /// through DictationEngine) writes asynchronously on its own queue, so this never blocks
  /// whichever thread the event happened on.
  var onConnectionEvent: ((_ kind: String, _ turnOpen: Bool, _ socketAgeS: Double?) -> Void)?
  private let mode: TranscriptionMode
  /// "auto" or a SpeechLanguage code.
  let language: String
  private let keyterms: [String]

  // Settlement. The server owes a transcript.final after speech_end, and that final
  // settles the turn (completeServerTurnIfReady). Partials are speculative and a final may
  // belong to an earlier segment, so the only other way out is this ceiling, counted from
  // the speech_end acknowledgement (attemptSettle). Checks on 2026-10-07 saw the terminal
  // final 0.1 to 0.25 s after speech_end.
  private static let settleMaxWait: Double = 2.20
  // Settlement and deadlines use monotonic time; keep the existing scheduling allowance.
  private static let settleTimerCushion: Double = 0.01
  private let settleQueue = DispatchQueue(label: "com.adhishthite.stok.settle")
  private var settleMaxWorkItem: DispatchWorkItem?  // fixed hard ceiling check
  private var reconnectWorkItem: DispatchWorkItem?
  private var reconnectAttempts: Int = 0
  // The server closes a socket that carries neither audio nor a ping for 60 seconds
  // (close 1008). An application-level ping every 20 seconds while idle keeps the session
  // open, and the pong proves the path, so a dead socket becomes a reconnect before the
  // next key press needs it. Verified 2026-10-07: 20-second pings held a session for
  // 140 seconds; without them it closed at 60.
  static let keepaliveIntervalSeconds = 20.0
  static let pongTimeoutSeconds = 10.0
  var keepaliveWorkItem: DispatchWorkItem?
  var pongDeadline: DispatchWorkItem?
  // A rejected key fails every attempt the same way, so retrying it forever only burns
  // battery. Count consecutive rejections and stop; an explicit connect() starts over.
  private static let maxAuthRejections = 3
  private var authRejectionCount = 0
  private var lastCloseIndicatedRejection = false

  private static let speechStartMessage = "{\"event\":\"speech_start\"}"
  private static let speechEndMessage = "{\"event\":\"speech_end\"}"
  private static let pingMessage = "{\"event\":\"ping\"}"
  /// The session's `stream_type`, under `lock`.
  private var streamType: String
  /// Set when stream_type changed during a turn; the turn's end opens the new session.
  private var reconnectForStreamType = false

  /// Switches stream_type. config.update cannot switch to or from "simulated" mid-session
  /// (verified 2026-10-07: a non-fatal invalid_config error), so the change opens a new
  /// session: now when idle, or as soon as an open turn ends.
  func setStreamType(_ value: String) {
    lock.lock()
    guard value != streamType else {
      lock.unlock()
      return
    }
    streamType = value
    let busy = turnOpen || isCommitting
    if busy { reconnectForStreamType = true }
    let reconnect = !busy && reconnectEnabled
    lock.unlock()
    if reconnect { connect(reason: "reconnect") }
  }

  // Live-route health during a turn, for the early REST hedge (audit F22). Partials used to
  // be the proof of life, but "simulated" sends none, so the turn also queues a ping behind
  // its audio about once a second. Any server message in the turn (pong, partial, final)
  // counts. The pong comes back only after the server has read the audio queued before it.
  // All under `lock`.
  static let turnPingIntervalSeconds = 1.0
  private var lastTurnPingAt: CFAbsoluteTime = 0
  private var turnSignalAt: CFAbsoluteTime?

  /// Seconds since the server last proved the live route alive during the current turn, or
  /// nil when it has not.
  var liveSignalAgeSeconds: Double? {
    lock.lock()
    defer { lock.unlock() }
    return turnSignalAt.map { ProcessInfo.processInfo.systemUptime - $0 }
  }

  init(
    apiKey: String,
    model: String = "saaras:v4",
    mode: TranscriptionMode = .standard,
    language: String = SpeechLanguage.automatic,
    keyterms: [String] = [],
    streamType: String = "fast"
  ) {
    self.apiKey = apiKey
    self.streamType = streamType
    self.model = model
    self.mode = mode
    self.language = language
    self.keyterms = keyterms
    super.init()
    let config = URLSessionConfiguration.default
    config.waitsForConnectivity = true
    config.timeoutIntervalForRequest = 10.0
    self.urlSession = URLSession(configuration: config, delegate: self, delegateQueue: nil)
  }

  /// The socket URL for one session. Every option is a query parameter; the key is not.
  static func sessionURL(
    model: String, mode: TranscriptionMode, language: String, keyterms: [String],
    streamType: String = "fast"
  ) -> URL? {
    guard var components = URLComponents(url: SarvamAPI.realtimeURL, resolvingAgainstBaseURL: false)
    else { return nil }
    var items = [
      URLQueryItem(
        name: "language_code", value: SpeechLanguage.realtimeCode(for: language)),
      URLQueryItem(name: "model", value: model),
      // Translate applies to finals only; partials stay in the spoken language.
      URLQueryItem(name: "mode", value: mode.rawValue),
      // The shortcut is the ground truth for when speech starts and ends. Server VAD would
      // end an utterance at a pause and, verified 2026-10-07, ignores `flush`, so a turn
      // could not be finished on key release without sending seconds of silence.
      URLQueryItem(name: "endpointing", value: SarvamAPI.endpointing),
      // "fast" streams partials for the live overlay; "simulated" sends finals only and
      // settles sooner (SarvamAPI.streamType).
      URLQueryItem(name: "stream_type", value: streamType),
      URLQueryItem(name: "encoding", value: "linear16"),
      URLQueryItem(name: "sample_rate", value: "16000"),
      // Stamps each final with end_s, which tells the final that answers speech_end apart
      // from an earlier segment's final that arrives late.
      URLQueryItem(name: "return_timestamps", value: "true"),
    ]
    // keyterms are a saaras:v4 feature; other models reject the parameter.
    if model.hasPrefix("saaras:v4"), let json = SarvamAPI.keytermsJSON(keyterms) {
      items.append(URLQueryItem(name: "keyterms", value: json))
    }
    components.queryItems = items
    // URLComponents leaves "+" alone in a query; the server would read it as a space.
    let encoded = components.percentEncodedQuery ?? ""
    components.percentEncodedQuery = encoded.replacingOccurrences(of: "+", with: "%2B")
    return components.url
  }

  func connect(expectedConnection: UInt64? = nil, reason: String = "reconnect") {
    guard !apiKey.isEmpty else { return }

    lock.lock()
    let streamType = self.streamType
    lock.unlock()
    guard
      let url = Self.sessionURL(
        model: model, mode: mode, language: language, keyterms: keyterms,
        streamType: streamType)
    else {
      Log.error("WS", "Invalid WebSocket URL.")
      return
    }

    var request = URLRequest(url: url)
    request.timeoutInterval = 10.0
    request.setValue(apiKey, forHTTPHeaderField: SarvamAPI.authHeader)

    let task = urlSession.webSocketTask(with: request)
    lock.lock()
    if let expected = expectedConnection, expected != connectionID || !reconnectEnabled {
      lock.unlock()
      task.cancel(with: .goingAway, reason: nil)
      return
    }
    reconnectWorkItem?.cancel()
    reconnectWorkItem = nil
    keepaliveWorkItem?.cancel()
    keepaliveWorkItem = nil
    pongDeadline?.cancel()
    pongDeadline = nil
    sessionEstablishedAt = 0
    lastCloseIndicatedRejection = false
    // Only a caller-initiated connect clears the rejection streak. Clearing it on the
    // reconnect path too would make the three-strike stop unreachable.
    if expectedConnection == nil { authRejectionCount = 0 }
    reconnectEnabled = true
    reconnectForStreamType = false
    connectionID &+= 1
    // Only a connect during an open turn counts. A heuristic finish closes its turn, then
    // retires the socket here before the engine reads the flag in settle().
    if turnOpen { turnConnectionChanged = true }
    let epoch = connectionID
    let old = webSocketTask
    self.webSocketTask = task
    readyState = false
    connectedState = false
    // Utterance indices and session audio time restart with every session.
    finalizedUtterances.removeAll()
    utteranceFloor = 0
    turnFirstUtteranceIdx = nil
    turnMaxUtteranceIdx = nil
    sessionAudioBytes = 0
    if turnOpen && turnSentAnyMessage {
      turnHasAudioGap = true
      discardPendingWritesLocked()
    }
    pendingConnectReason = reason
    let turnOpenAtConnect = turnOpen
    lock.unlock()
    old?.cancel(with: .goingAway, reason: nil)
    task.resume()

    // No per-attempt "connecting" line: the single "session ready" line logged once the
    // session begins names this attempt's reason.
    Log.debug("WS", "Connecting to Sarvam realtime STT (\(model), reason=\(reason))...")
    listenForMessages(task: task, epoch: epoch)
    onConnectionEvent?(Self.connectionEventKind(forConnectReason: reason), turnOpenAtConnect, nil)
  }

  /// Maps the free-form `reason` a connect attempt is tagged with to one of the fixed
  /// connection_events kinds. Every reason this client passes to connect() ("startup",
  /// "wake", and the default "reconnect") is named explicitly; anything else still gets a
  /// kind rather than being dropped.
  private static func connectionEventKind(forConnectReason reason: String) -> String {
    switch reason {
    case "startup": return "connect_startup"
    case "wake": return "connect_wake"
    default: return "connect_reconnect"
    }
  }

  /// `reason` only distinguishes a failed idle keepalive ("keepalive") from every other
  /// cause for the connection_events kind it reports; it changes no reconnect behavior.
  func connectionFailed(epoch: UInt64, error: Error, reason: String = "error") {
    lock.lock()
    guard epoch == connectionID else {
      lock.unlock()
      return
    }
    let turnOpenAtFailure = turnOpen
    let socketAgeS =
      sessionEstablishedAt > 0 ? ProcessInfo.processInfo.systemUptime - sessionEstablishedAt : nil
    turnConnectionChanged = true
    readyState = false
    connectedState = false
    if turnOpen && turnSentAnyMessage {
      turnHasAudioGap = true
      discardPendingWritesLocked()
    }
    let completion = hasFiredTurnCompletion ? nil : turnCompletion
    turnCompletion = nil
    if completion != nil {
      hasFiredTurnCompletion = true
      isCommitting = false
    }
    keepaliveWorkItem?.cancel()
    keepaliveWorkItem = nil
    pongDeadline?.cancel()
    pongDeadline = nil
    // Sarvam accepts the upgrade (101) and then refuses a bad key with a fatal error event
    // and close 1003, so the rejection is read from that event or the close, not the HTTP
    // status. A refused upgrade (401/403) still counts. Any other failure on a completed
    // upgrade clears the streak; a transport failure with no response leaves it alone.
    let status = (webSocketTask?.response as? HTTPURLResponse)?.statusCode
    if Self.isAuthRejection(status: status) || lastCloseIndicatedRejection {
      authRejectionCount += 1
    } else if status != nil {
      authRejectionCount = 0
    }
    let stopReconnecting = authRejectionCount >= Self.maxAuthRejections
    if stopReconnecting { reconnectEnabled = false }
    lock.unlock()
    onConnectionEvent?(
      reason == "keepalive" ? "lost_keepalive" : "lost_error", turnOpenAtFailure, socketAgeS)
    completion?(.failure(error))
    if stopReconnecting {
      Log.error("WS", "API key rejected; not reconnecting.")
      onAuthRejected?()
      return
    }
    scheduleReconnect(epoch: epoch)
  }

  private static func isAuthRejection(status: Int?) -> Bool {
    guard let status else { return false }
    return status == 401 || status == 403
  }

  /// Close 1003 covers a rate limit and an exhausted quota as well as a bad key, so only a
  /// reason that names the key counts as a rejection. The reason text is never logged.
  func urlSession(
    _ session: URLSession, webSocketTask: URLSessionWebSocketTask,
    didCloseWith closeCode: URLSessionWebSocketTask.CloseCode, reason: Data?
  ) {
    let text = reason.flatMap { String(data: $0, encoding: .utf8) } ?? ""
    let rejected = Self.closeIndicatesKeyRejection(code: closeCode.rawValue, reason: text)
    lock.lock()
    if webSocketTask === self.webSocketTask, rejected { lastCloseIndicatedRejection = true }
    lock.unlock()
  }

  static func closeIndicatesKeyRejection(code: Int, reason: String) -> Bool {
    guard code == 1003 else { return false }
    let lowered = reason.lowercased()
    return lowered.contains("subscription key") || lowered.contains("api key")
      || lowered.contains("authentication")
  }

  /// A fatal error event that names the key. Verified 2026-10-07: a bad key arrives as
  /// `{"event":"error","code":"invalid_subscription_key","is_fatal":true,"status_code":401}`.
  static func errorIndicatesKeyRejection(code: String?, statusCode: Int?) -> Bool {
    code == "invalid_subscription_key" || statusCode == 401 || statusCode == 403
  }

  private func listenForMessages(task: URLSessionWebSocketTask, epoch: UInt64) {
    task.receive { [weak self] result in
      guard let self = self else { return }
      switch result {
      case .success(let message):
        self.handleIncomingMessage(message, epoch: epoch)
        self.lock.lock()
        let current = self.connectionID == epoch
        self.lock.unlock()
        if current { self.listenForMessages(task: task, epoch: epoch) }
      case .failure(let error): self.connectionFailed(epoch: epoch, error: error)
      }
    }
  }

  func handleIncomingMessage(_ message: URLSessionWebSocketTask.Message, epoch: UInt64) {
    var rawData: Data?
    switch message {
    case .string(let str):
      rawData = str.data(using: .utf8)
    case .data(let data):
      rawData = data
    @unknown default:
      break
    }

    guard let data = rawData,
      let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
      let event = json["event"] as? String
    else {
      return
    }

    // Actions to perform once the lock is released: logging, meter text, and callbacks
    // must never run while `lock` is held.
    var fatalError: (code: String, task: URLSessionWebSocketTask?)? = nil
    var nonFatalErrorCode: String? = nil
    var didBeginSession = false
    var connectReasonForLog = ""
    var liveTextUpdate: (elapsedMs: Double, fullText: String)? = nil
    var shouldCompleteServerTurn = false
    var messageTurn: UInt64 = 0

    lock.lock()

    guard epoch == connectionID else {
      lock.unlock()
      return
    }

    messageTurn = turnID
    // Any message but an error proves the live route is answering during this turn.
    if turnOpen, event != "error" { turnSignalAt = ProcessInfo.processInfo.systemUptime }

    // Round-trip split: the first server message of any kind after this turn's
    // commit, whatever it carries.
    if isCommitting, commitToFirstMsgMs == nil {
      commitToFirstMsgMs = (ProcessInfo.processInfo.systemUptime - turnCommitTime) * 1000.0
    }

    switch event {
    case "session.begin":
      connectedState = true
      readyState = true
      reconnectAttempts = 0
      didBeginSession = true
      connectReasonForLog = pendingConnectReason
      sessionEstablishedAt = ProcessInfo.processInfo.systemUptime
      scheduleKeepaliveLocked(epoch: epoch)
      // The session began, so this key works.
      authRejectionCount = 0
      lastCloseIndicatedRejection = false

    case "pong":
      pongDeadline?.cancel()
      pongDeadline = nil

    case "error":
      let code = (json["code"] as? String) ?? "unknown"
      if (json["is_fatal"] as? Bool) ?? true {
        if Self.errorIndicatesKeyRejection(code: code, statusCode: json["status_code"] as? Int) {
          lastCloseIndicatedRejection = true
        }
        fatalError = (code, webSocketTask)
      } else {
        nonFatalErrorCode = code
      }

    case "transcript.partial", "transcript.final":
      let isFinal = event == "transcript.final"
      let index = json["utterance_idx"] as? Int
      // A final for this utterance already arrived: this message is stale or a duplicate.
      if let index, index < utteranceFloor || finalizedUtterances.contains(index) { break }
      if isFinal, let index { finalizedUtterances.insert(index) }
      guard turnOpen else { break }
      if let index {
        if turnFirstUtteranceIdx == nil { turnFirstUtteranceIdx = index }
        turnMaxUtteranceIdx = max(turnMaxUtteranceIdx ?? index, index)
      }
      let text = (json["text"] as? String) ?? ""
      let endSeconds = (json["end_s"] as? NSNumber)?.doubleValue
      var updatedText: String? = nil
      if isFinal {
        applyFinal(text, index: index)
        updatedText = mergedTranscript()
      } else if !text.isEmpty {
        applyInterim(text, index: index)
        updatedText = mergedTranscript()
      }

      // The final that answers speech_end ends the turn, and it must be the last segment: a
      // long turn is split by the server, and an earlier segment's final can arrive after
      // speech_end before any event for the next segment. With end_s, the last segment is the
      // one that ends where this turn's audio ended (fixed at beginCommit, once every audio
      // write is acknowledged). Without end_s, only a turn too short to have been split is
      // trusted. The decision does not wait for speech_end's own send acknowledgement: the
      // server can answer first, and the completion below still waits for it.
      var terminal = false
      if isFinal, isCommitting, !turnHasAudioGap, !hasFiredTurnCompletion {
        if let endSeconds {
          let endBytes = Double(turnEndAudioBytes ?? sessionAudioBytes)
          terminal =
            endSeconds * Double(SarvamAPI.pcmBytesPerSecond)
            >= endBytes - Self.finalEndToleranceSeconds * Double(SarvamAPI.pcmBytesPerSecond)
        } else {
          let unsplit =
            index == nil || (turnFirstUtteranceIdx == index && turnMaxUtteranceIdx == index)
          terminal =
            unsplit
            && Double(turnAudioBytes)
              < Self.unsplitTurnMaxSeconds * Double(SarvamAPI.pcmBytesPerSecond)
        }
        if terminal { turnTerminalUtteranceIdx = index }
      }

      let now = ProcessInfo.processInfo.systemUptime
      if updatedText != nil || isFinal {
        lastTokenReceivedTime = now
        if isCommitting {
          // Round-trip split: commit_to_final_ms is the last transcription message received
          // before settle, so this is overwritten on every post-commit update.
          commitToFinalMs = (now - turnCommitTime) * 1000.0
        }
      }
      if terminal {
        serverCompletionReceived = true
        commitToTurnCompleteMs = (now - turnCommitTime) * 1000.0
      }
      if let newText = updatedText, !newText.isEmpty || !currentTurnText.isEmpty {
        if currentTurnText.isEmpty && firstTokenLatencyMs == 0 && turnCommitTime > 0 {
          firstTokenLatencyMs = (now - turnCommitTime) * 1000.0
        }
        // Separate measurement: how long the service took to produce anything at all,
        // counted from the turn's speech_start rather than from the key release.
        if firstInterimLatencyMs == 0 && turnStartTime > 0 && !newText.isEmpty {
          firstInterimLatencyMs = (now - turnStartTime) * 1000.0
        }
        currentTurnText = newText
        let elapsedMs = turnCommitTime > 0 ? (now - turnCommitTime) * 1000.0 : 0
        liveTextUpdate = (elapsedMs: elapsedMs, fullText: currentTurnText)
      }
      shouldCompleteServerTurn = serverCompletionReceived && commitWritesComplete

    default:
      // vad.*, config.updated, session.end: nothing to do. A session.end is followed by a
      // close, which the receive loop reports as a failure and reconnects from.
      break
    }

    lock.unlock()

    // Logging & callbacks all run off the lock.
    if let code = nonFatalErrorCode {
      Log.warn("WS", "Server reported a non-fatal error (\(code)).")
    }
    if let fatal = fatalError {
      // The server closes right after a fatal error. Cancelling the task makes the receive
      // loop fail now, so the single connectionFailed path handles it exactly once.
      Log.warn("WS", "Server ended the live session (\(fatal.code)).")
      fatal.task?.cancel(with: .goingAway, reason: nil)
    }
    if didBeginSession {
      pumpWrites()
      Log.info("WS", "Live session ready (\(connectReasonForLog), \(model))")
    }
    // Callbacks fire before any terminal write: a slow consumer must never delay the HUD
    // update or the turn's completion. The completion is invoked directly; its only consumer
    // immediately hops onto the app's sessionQueue.
    if let update = liveTextUpdate {
      onLiveTextUpdate?(update.fullText)
      Log.meter(
        "[STREAM] \(update.fullText.count) characters received in \(String(format: "%.0f", update.elapsedMs)) ms"
      )
    }
    if shouldCompleteServerTurn { completeServerTurnIfReady(turn: messageTurn) }
  }

  // MARK: Segment transcript accumulator (all helpers assume `lock` is held)

  /// Clears the turn's transcript state.
  func resetTranscriptLocked() {
    currentTurnText = ""
    indexedFinals = [:]
    committedTranscript = ""
    interimTranscript = ""
    interimIndex = nil
  }

  private func mergedTranscript() -> String {
    // Finals and the in-progress partial in utterance order; unindexed text goes last.
    var indexed = indexedFinals
    if !interimTranscript.isEmpty, let index = interimIndex, indexed[index] == nil {
      indexed[index] = interimTranscript
    }
    var parts = indexed.keys.sorted().compactMap { indexed[$0] }
    if !committedTranscript.isEmpty { parts.append(committedTranscript) }
    if !interimTranscript.isEmpty, interimIndex == nil { parts.append(interimTranscript) }
    return parts.reduce("") { merged, part in
      if merged.isEmpty { return part }
      let needsSpace =
        !(merged.hasSuffix(" ") || merged.hasSuffix("\n") || part.hasPrefix(" "))
      return merged + (needsSpace ? " " : "") + part
    }
  }

  /// A partial carries the whole of its own utterance so far, so it replaces the previous
  /// partial. Only a partial without an index falls back to text matching.
  private func applyInterim(_ text: String, index: Int?) {
    guard index == nil else {
      interimTranscript = text
      interimIndex = index
      return
    }
    interimIndex = nil
    if !committedTranscript.isEmpty && text.hasPrefix(committedTranscript) {
      interimTranscript = String(text.dropFirst(committedTranscript.count))
    } else {
      interimTranscript = text
    }
  }

  private func applyFinal(_ text: String, index: Int?) {
    if let index {
      if !text.isEmpty { indexedFinals[index] = text }
      if interimIndex == index || interimIndex == nil {
        interimTranscript = ""
        interimIndex = nil
      }
      return
    }
    if !text.isEmpty {
      applyUnindexedFinal(text)
    } else {
      interimTranscript = ""
      interimIndex = nil
    }
  }

  /// Text fallback for a final with no utterance index: without an index there is no other
  /// way to tell a cumulative or repeated final from new speech.
  private func applyUnindexedFinal(_ text: String) {
    if committedTranscript.isEmpty {
      committedTranscript = text
    } else if text.hasPrefix(committedTranscript) {
      // Cumulative final covering the whole turn - replace wholesale.
      committedTranscript = text
    } else if committedTranscript.hasSuffix(text) {
      // Duplicate re-send of the segment just committed - nothing new.
    } else {
      // A final can restate the tail of what is already committed while matching neither a
      // prefix nor a suffix, and appending it whole repeats those words. Drop the overlap and
      // append only what is actually new.
      let overlap = Self.transcriptOverlapLength(committed: committedTranscript, incoming: text)
      let addition = String(text.dropFirst(overlap))
      guard !addition.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
        interimTranscript = ""
        interimIndex = nil
        return
      }
      let needsSpace =
        !(committedTranscript.hasSuffix(" ") || committedTranscript.hasSuffix("\n")
        || addition.hasPrefix(" "))
      committedTranscript += (needsSpace ? " " : "") + addition
    }
    interimTranscript = ""
    interimIndex = nil
  }

  /// Length, in characters, of the longest tail of `committed` that is also the head of
  /// `incoming`. Only whole-word overlaps count: trimming mid-word would splice two
  /// different words together, which is worse than leaving a repeat. The scan is capped so
  /// a long transcript cannot turn every final into quadratic work.
  static func transcriptOverlapLength(
    committed: String, incoming: String, limit: Int = 200
  ) -> Int {
    let tail = Array(committed.suffix(limit))
    let head = Array(incoming.prefix(limit))
    // Position 0 of the tail only starts a word when the tail is the whole committed text.
    let tailStartsAtWordBoundary = tail.count == committed.count
    var length = min(tail.count, head.count)
    while length > 0 {
      let start = tail.count - length
      if Array(tail.suffix(length)) == Array(head.prefix(length)),
        isWordStart(tail, index: start, includingZero: tailStartsAtWordBoundary),
        isWordEnd(head, index: length)
      {
        return length
      }
      length -= 1
    }
    return 0
  }

  /// True when `index` begins a word: a position right after whitespace, or the start of the
  /// scanned tail when that tail is the whole committed text.
  private static func isWordStart(
    _ characters: [Character], index: Int, includingZero: Bool
  ) -> Bool {
    index == 0 ? includingZero : characters[index - 1].isWhitespace
  }

  /// True when `index` ends a word: the end of the incoming head, a position followed by
  /// whitespace, or a position right after whitespace (the overlap ended with a space).
  private static func isWordEnd(_ characters: [Character], index: Int) -> Bool {
    if index == characters.count { return true }
    return characters[index].isWhitespace || characters[index - 1].isWhitespace
  }

  // Re-validates the settle rules against current authoritative state and, if any rule
  // holds, performs the once-only settle sequence. Safe to call redundantly from a stale
  // or overlapping timer: state (isCommitting/hasFiredTurnCompletion) is the source of
  // truth, not which timer fired.
  func attemptSettle(turn: UInt64) {
    lock.lock()
    guard turn == turnID, isCommitting, commitWritesComplete, !hasFiredTurnCompletion else {
      lock.unlock()
      return
    }

    if turnHasAudioGap {
      let epoch = connectionID
      lock.unlock()
      connectionFailed(
        epoch: epoch,
        error: NSError(
          domain: "Stok", code: -4,
          userInfo: [NSLocalizedDescriptionKey: "Live connection missed part of the recording."]))
      return
    }
    if serverCompletionReceived, allSegmentsFinalizedLocked() {
      lock.unlock()
      completeServerTurnIfReady(turn: turn)
      return
    }
    // No final has ended the turn, or an earlier segment's final is still missing. Partials are speculative and a final may belong to an
    // earlier segment, so neither settles the turn early: it waits for the terminal final,
    // and only past settleMaxWait takes whatever text it has.
    let now = ProcessInfo.processInfo.systemUptime
    guard now - commitWritesCompletedAt >= Self.settleMaxWait else {
      lock.unlock()
      return
    }
    let text = currentTurnText
    // Partials are provisional: the output mode applies to finals only, and in translate mode
    // a partial is still in the spoken language. Text with a partial-only utterance, or with
    // an utterance whose final never came, is not the requested output, so the live route
    // fails into REST (which honors mode and language) instead of pasting it.
    // Only confirmed terminal coverage settles from the socket: the final whose end_s reached
    // the turn's end (or the unsplit-short-turn rule), with every utterance through it
    // finalized. Observed utterances alone prove nothing: without partials ("simulated") a
    // stalled long turn looks complete, and a turn with no events at all is a stalled route,
    // not the service's no-speech verdict (that is an empty terminal final).
    let incomplete = !(serverCompletionReceived && allSegmentsFinalizedLocked())

    completedFirstInterimMs = firstInterimLatencyMs > 0 ? firstInterimLatencyMs : nil
    hasFiredTurnCompletion = true
    isCommitting = false
    turnOpen = false
    discardPendingWritesLocked()
    settlePathValue = "timeout"
    settleMaxWorkItem?.cancel()
    settleMaxWorkItem = nil

    let totalLatencyMs = (now - turnCommitTime) * 1000.0
    resetTranscriptLocked()
    let firstToken = firstTokenLatencyMs
    firstTokenLatencyMs = 0
    firstInterimLatencyMs = 0
    let cb = turnCompletion
    turnCompletion = nil
    lock.unlock()

    // A timeout has no server boundary. Retire its socket before another turn can accept
    // delayed words from this one.
    connect()

    // Completion before the terminal write, and directly on settleQueue - the consumer
    // re-dispatches onto sessionQueue itself.
    if incomplete {
      Log.warn("WS", "Live transcript incomplete at the timeout; handing the turn to REST.")
      cb?(.failure(Self.incompleteTranscriptError()))
    } else if !text.isEmpty {
      cb?(.success((text: text, firstTokenMs: firstToken, totalMs: totalLatencyMs)))
    } else {
      cb?(.failure(Self.noSpeechError()))
    }
    Log.endMeter()
  }

  static func incompleteTranscriptError() -> NSError {
    NSError(
      domain: "Stok", code: -6,
      userInfo: [NSLocalizedDescriptionKey: "Live transcript was incomplete at the timeout."])
  }

  private static func noSpeechError() -> NSError {
    NSError(
      domain: "Stok", code: -2,
      userInfo: [NSLocalizedDescriptionKey: "No speech recognized before timeout."])
  }

  func startNewTurn() {
    lock.lock()
    let abandoned = turnOpen
    lock.unlock()
    if abandoned { abandonTurn() }
    lock.lock()
    turnID &+= 1
    turnOpen = true
    discardPendingWritesLocked()
    turnHasAudioGap = false
    turnSentAnyMessage = false
    turnWrites = DispatchGroup()
    self.settleMaxWorkItem?.cancel()
    self.settleMaxWorkItem = nil
    self.isCommitting = false
    commitWritesComplete = false
    serverCompletionReceived = false
    self.settlePathValue = nil
    resetTranscriptLocked()
    turnAudioBytes = 0
    turnEndAudioBytes = nil
    self.firstTokenLatencyMs = 0
    self.firstInterimLatencyMs = 0
    self.completedFirstInterimMs = nil
    self.turnStartTime = ProcessInfo.processInfo.systemUptime
    lastTurnPingAt = turnStartTime
    turnSignalAt = nil
    self.hasFiredTurnCompletion = false
    self.turnCommitTime = 0
    self.lastTokenReceivedTime = 0
    turnTerminalUtteranceIdx = nil
    self.turnFirstUtteranceIdx = nil
    self.turnMaxUtteranceIdx = nil
    self.turnCompletion = nil
    self.turnConnectionChanged = false
    self.commitToLastSendMs = nil
    self.commitToFirstMsgMs = nil
    self.commitToFinalMs = nil
    self.commitToTurnCompleteMs = nil
    lock.unlock()

    // The key press is the start of speech.
    sendTurnMessage(Self.speechStartMessage)
  }

  // Base64's alphabet (A-Za-z0-9+/=) needs no JSON escaping, so the fixed-shape
  // envelope is built once and the payload is spliced in directly, skipping
  // JSONSerialization on the hot per-chunk (CHUNK_MS, ~100ms) path.
  private static let audioChunkJSONPrefix = "{\"event\":\"audio_input\",\"audio\":\""
  private static let audioChunkJSONSuffix = "\"}"

  // Reservations include the in-flight write. Invalidating a turn releases them once;
  // late transport callbacks cannot release reservations belonging to the next turn.
  private func discardPendingWritesLocked() {
    writeDeadline?.cancel()
    writeDeadline = nil
    for write in pendingWrites { write.writes.leave() }
    pendingWrites.removeAll(keepingCapacity: true)
    pendingWriteBytes = 0
    writeInFlight = false
  }

  private func armWriteDeadlineLocked() {
    writeDeadline?.cancel()
    guard let first = pendingWrites.first else {
      writeDeadline = nil
      return
    }
    let turn = turnID
    let id = first.id
    let item = DispatchWorkItem { [weak self] in
      guard let self = self else { return }
      self.lock.lock()
      guard self.turnID == turn, self.pendingWrites.first?.id == id else {
        self.lock.unlock()
        return
      }
      self.turnHasAudioGap = true
      self.discardPendingWritesLocked()
      let epoch = self.connectionID
      self.lock.unlock()
      self.connectionFailed(epoch: epoch, error: Self.writeBacklogError())
    }
    writeDeadline = item
    let remaining = max(
      0, first.admittedAt + Self.maxPendingWriteAge - ProcessInfo.processInfo.systemUptime)
    sendQueue.asyncAfter(deadline: .now() + remaining, execute: item)
  }

  private static func writeBacklogError() -> NSError {
    NSError(
      domain: "Stok", code: -4,
      userInfo: [NSLocalizedDescriptionKey: "Live audio delivery exceeded its queue budget."])
  }

  func sendTurnMessage(_ text: String, audioBytes: Int = 0) {
    lock.lock()
    guard turnOpen, !turnHasAudioGap else {
      lock.unlock()
      return
    }
    let now = ProcessInfo.processInfo.systemUptime
    if text.utf8.count > Self.maxPendingWriteBytes - pendingWriteBytes
      || pendingWrites.first.map({ now - $0.admittedAt >= Self.maxPendingWriteAge }) == true
    {
      turnHasAudioGap = true
      discardPendingWritesLocked()
      let epoch = connectionID
      lock.unlock()
      connectionFailed(epoch: epoch, error: Self.writeBacklogError())
      return
    }
    nextWriteID &+= 1
    turnWrites.enter()
    pendingWrites.append(
      PendingWrite(
        id: nextWriteID, text: text, admittedAt: now, writes: turnWrites, audioBytes: audioBytes))
    pendingWriteBytes += text.utf8.count
    if pendingWrites.count == 1 { armWriteDeadlineLocked() }
    lock.unlock()
    pumpWrites()
  }

  private func pumpWrites() {
    sendQueue.async { [weak self] in
      guard let self = self else { return }
      self.lock.lock()
      guard self.readyState, self.turnOpen, !self.turnHasAudioGap,
        !self.writeInFlight, let write = self.pendingWrites.first,
        let task = self.webSocketTask
      else {
        self.lock.unlock()
        return
      }
      self.writeInFlight = true
      self.turnSentAnyMessage = true
      let epoch = self.connectionID
      let turn = self.turnID
      self.lock.unlock()
      self.writeTransport(task, write.text) { [weak self] error in
        guard let self = self else { return }
        self.lock.lock()
        guard self.turnID == turn, self.connectionID == epoch,
          self.pendingWrites.first?.id == write.id
        else {
          self.lock.unlock()
          return
        }
        if let error = error {
          self.turnHasAudioGap = true
          self.discardPendingWritesLocked()
          self.lock.unlock()
          self.connectionFailed(epoch: epoch, error: error)
          return
        }
        self.pendingWrites.removeFirst()
        self.pendingWriteBytes -= write.text.utf8.count
        self.sessionAudioBytes += write.audioBytes
        self.turnAudioBytes += write.audioBytes
        self.writeInFlight = false
        write.writes.leave()
        self.armWriteDeadlineLocked()
        self.lock.unlock()
        self.pumpWrites()
      }
    }
  }

  func sendAudioChunk(_ pcmChunk: Data) {
    sendTurnMessage(
      Self.audioChunkJSONPrefix + pcmChunk.base64EncodedString() + Self.audioChunkJSONSuffix,
      audioBytes: pcmChunk.count)
    lock.lock()
    let now = ProcessInfo.processInfo.systemUptime
    let ping =
      turnOpen && !turnHasAudioGap && now - lastTurnPingAt >= Self.turnPingIntervalSeconds
    if ping { lastTurnPingAt = now }
    lock.unlock()
    if ping { sendTurnMessage(Self.pingMessage) }
  }

  func commitTurn(
    completion:
      @escaping (Result<(text: String, firstTokenMs: Double, totalMs: Double), Error>) -> Void
  ) {
    lock.lock()
    let writes = turnWrites
    let expectedTurn = turnID
    lock.unlock()
    writes.notify(queue: sendQueue) { [weak self] in
      self?.beginCommit(turn: expectedTurn, completion: completion)
    }
  }

  func beginCommit(
    turn expectedTurn: UInt64,
    completion:
      @escaping (Result<(text: String, firstTokenMs: Double, totalMs: Double), Error>) -> Void
  ) {
    lock.lock()
    guard expectedTurn == turnID, turnOpen, readyState, !turnHasAudioGap else {
      lock.unlock()
      completion(
        .failure(
          NSError(
            domain: "Stok", code: -4,
            userInfo: [NSLocalizedDescriptionKey: "Live connection missed part of the recording."]))
      )
      return
    }
    self.turnCommitTime = ProcessInfo.processInfo.systemUptime
    self.isCommitting = true
    commitWritesComplete = false
    serverCompletionReceived = false
    // commitTurn waits for every earlier write, so all of this turn's audio is acknowledged:
    // this is where the turn's audio ends in session time.
    turnEndAudioBytes = sessionAudioBytes
    self.turnCompletion = completion
    self.hasFiredTurnCompletion = false
    lock.unlock()

    // The key release is the end of speech. speech_end is the only terminator: the server
    // finalizes the buffered utterance and answers with transcript.final.
    sendTurnMessage(Self.speechEndMessage)

    lock.lock()
    let terminalWrites = turnWrites
    lock.unlock()
    terminalWrites.notify(queue: sendQueue) { [weak self] in
      self?.finishCommitWrites(turn: expectedTurn)
    }
  }

  private func finishCommitWrites(turn expectedTurn: UInt64) {
    lock.lock()
    guard turnID == expectedTurn, isCommitting, !hasFiredTurnCompletion,
      !turnHasAudioGap, readyState
    else {
      lock.unlock()
      return
    }
    commitWritesComplete = true
    commitWritesCompletedAt = ProcessInfo.processInfo.systemUptime
    // Round-trip split: the last audio frame and speech_end are on the wire once every
    // write this commit queued has been acknowledged by its completion handler, exactly the
    // instant this notify fires.
    commitToLastSendMs = (commitWritesCompletedAt - turnCommitTime) * 1000.0
    let maxItem = DispatchWorkItem { [weak self] in self?.attemptSettle(turn: expectedTurn) }
    settleMaxWorkItem?.cancel()
    settleMaxWorkItem = maxItem
    lock.unlock()
    // A terminal final that arrived before this acknowledgement settles the turn now.
    attemptSettle(turn: expectedTurn)
    settleQueue.asyncAfter(
      deadline: .now() + Self.settleMaxWait + Self.settleTimerCushion, execute: maxItem)
  }

  /// Settles the turn on the server's own boundary: the final that answered speech_end. An
  /// empty final there is the service's verdict that the turn held no speech.
  /// True when every utterance of this turn, from the first index it can own
  /// (`utteranceFloor`) through the terminal one, has its final. Finals can arrive out of
  /// order, so the terminal final alone does not mean the turn's text is complete. Caller
  /// holds `lock`.
  private func allSegmentsFinalizedLocked() -> Bool {
    guard let terminal = turnTerminalUtteranceIdx, terminal >= utteranceFloor else { return true }
    return (utteranceFloor...terminal).allSatisfy { finalizedUtterances.contains($0) }
  }

  private func completeServerTurnIfReady(turn expectedTurn: UInt64) {
    lock.lock()
    guard turnID == expectedTurn, isCommitting, commitWritesComplete, serverCompletionReceived,
      !turnHasAudioGap, !hasFiredTurnCompletion, allSegmentsFinalizedLocked()
    else {
      lock.unlock()
      return
    }
    turnOpen = false
    completedFirstInterimMs = firstInterimLatencyMs > 0 ? firstInterimLatencyMs : nil
    hasFiredTurnCompletion = true
    isCommitting = false
    settlePathValue = "server_final"
    // Every utterance up to the terminal one has its final (checked above), so nothing at or
    // below it can matter. A turn missing one ends by timeout instead, which reconnects.
    if let terminalIndex = turnTerminalUtteranceIdx {
      utteranceFloor = max(utteranceFloor, terminalIndex + 1)
      finalizedUtterances = finalizedUtterances.filter { $0 >= utteranceFloor }
    }
    settleMaxWorkItem?.cancel()
    settleMaxWorkItem = nil
    let elapsed = (ProcessInfo.processInfo.systemUptime - turnCommitTime) * 1000
    let text = currentTurnText
    resetTranscriptLocked()
    let first = firstTokenLatencyMs
    firstTokenLatencyMs = 0
    firstInterimLatencyMs = 0
    let callback = turnCompletion
    turnCompletion = nil
    let reconnect = reconnectForStreamType
    lock.unlock()
    if reconnect { connect(reason: "reconnect") }
    if text.isEmpty {
      callback?(.failure(Self.noSpeechError()))
    } else {
      callback?(.success((text: text, firstTokenMs: first, totalMs: elapsed)))
    }
    Log.endMeter()
  }

  /// Arms the next idle keepalive ping. Caller holds `lock`.
  private func scheduleKeepaliveLocked(epoch: UInt64) {
    keepaliveWorkItem?.cancel()
    let item = DispatchWorkItem { [weak self] in self?.sendKeepalivePing(epoch: epoch) }
    keepaliveWorkItem = item
    settleQueue.asyncAfter(deadline: .now() + Self.keepaliveIntervalSeconds, execute: item)
  }

  func sendKeepalivePing(epoch: UInt64) {
    lock.lock()
    keepaliveWorkItem = nil
    guard epoch == connectionID, reconnectEnabled, readyState, let task = webSocketTask else {
      lock.unlock()
      return
    }
    // A turn in progress streams audio, which is its own proof of life. The timer is
    // re-armed either way.
    let idle = !turnOpen && !isCommitting
    let socketAgeSeconds = ProcessInfo.processInfo.systemUptime - sessionEstablishedAt
    scheduleKeepaliveLocked(epoch: epoch)
    var deadline: DispatchWorkItem?
    if idle, pongDeadline == nil {
      let item = DispatchWorkItem { [weak self] in
        self?.keepaliveFailed(epoch: epoch, socketAgeSeconds: socketAgeSeconds)
      }
      pongDeadline = item
      deadline = item
    }
    lock.unlock()
    guard idle else { return }
    if let deadline {
      settleQueue.asyncAfter(deadline: .now() + Self.pongTimeoutSeconds, execute: deadline)
    }
    writeTransport(task, Self.pingMessage) { [weak self] error in
      guard error != nil else { return }
      self?.keepaliveFailed(epoch: epoch, socketAgeSeconds: socketAgeSeconds)
    }
  }

  /// A ping that could not be sent, or whose pong never came, means the socket is gone.
  /// Take the same path a receive error takes.
  private func keepaliveFailed(epoch: UInt64, socketAgeSeconds: Double) {
    lock.lock()
    let current = epoch == connectionID
    pongDeadline?.cancel()
    pongDeadline = nil
    lock.unlock()
    guard current else { return }
    Log.warn(
      "WS",
      "Keepalive ping failed; treating the live connection as lost (idle, socket age "
        + "\(String(format: "%.0f", socketAgeSeconds))s).")
    connectionFailed(
      epoch: epoch,
      error: NSError(
        domain: "Stok", code: -5,
        userInfo: [NSLocalizedDescriptionKey: "Live connection stopped answering."]),
      reason: "keepalive")
  }

  private func scheduleReconnect(epoch: UInt64, reason: String = "reconnect") {
    lock.lock()
    guard epoch == connectionID, reconnectEnabled, reconnectWorkItem == nil else {
      lock.unlock()
      return
    }
    reconnectAttempts += 1
    let delay = min(10.0, pow(2.0, Double(min(reconnectAttempts, 4))))
    let item = DispatchWorkItem { [weak self] in
      guard let self = self else { return }
      self.lock.lock()
      let current = self.connectionID == epoch && self.reconnectEnabled
      self.reconnectWorkItem = nil
      self.lock.unlock()
      if current {
        self.connect(expectedConnection: epoch, reason: reason)
      }
    }
    reconnectWorkItem = item
    lock.unlock()
    settleQueue.asyncAfter(deadline: .now() + delay, execute: item)
  }

  func abandonTurn() {
    lock.lock()
    let needsRotation = turnOpen
    turnOpen = false
    discardPendingWritesLocked()
    turnCompletion = nil
    isCommitting = false
    hasFiredTurnCompletion = true
    settleMaxWorkItem?.cancel()
    lock.unlock()
    // speech_start already went out for this turn. A fresh session guarantees none of its
    // audio or transcript leaks into the next one.
    if needsRotation { connect() }
  }

  func disconnect() {
    lock.lock()
    connectionID &+= 1
    let hadConnection = webSocketTask != nil
    let socketAgeS =
      sessionEstablishedAt > 0 ? ProcessInfo.processInfo.systemUptime - sessionEstablishedAt : nil
    let turnOpenAtDisconnect = turnOpen
    turnConnectionChanged = true
    reconnectEnabled = false
    sessionEstablishedAt = 0
    reconnectWorkItem?.cancel()
    reconnectWorkItem = nil
    keepaliveWorkItem?.cancel()
    keepaliveWorkItem = nil
    pongDeadline?.cancel()
    pongDeadline = nil
    settleMaxWorkItem?.cancel()
    settleMaxWorkItem = nil
    let task = webSocketTask
    webSocketTask = nil
    connectedState = false
    readyState = false
    if turnOpen { turnHasAudioGap = true }
    discardPendingWritesLocked()
    let completion = turnCompletion
    turnCompletion = nil
    isCommitting = false
    lock.unlock()
    task?.cancel(with: .normalClosure, reason: nil)
    if hadConnection { onConnectionEvent?("closed_by_client", turnOpenAtDisconnect, socketAgeS) }
    completion?(
      .failure(
        NSError(
          domain: "Stok", code: -4,
          userInfo: [NSLocalizedDescriptionKey: "Live connection closed."])))
  }
  func shutdown() {
    disconnect()
    urlSession.invalidateAndCancel()
  }

}
