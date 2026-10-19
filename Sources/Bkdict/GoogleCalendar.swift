import AppKit
import CryptoKit
import Foundation
import Network

/// Google Calendar, connected straight from the app: OAuth for desktop apps (PKCE, loopback redirect), the refresh
/// token in the Keychain, events read from the Calendar API (see docs/reunioes.md, "Calendário — Google Agenda").
@MainActor
final class GoogleCalendar: ObservableObject {
    enum Failure: LocalizedError {
        case notConfigured, cancelled, timedOut, denied(String), token(String), api(String)

        var errorDescription: String? {
            switch self {
            case .notConfigured: "A credencial do Google ainda não foi configurada."
            case .cancelled: "A conexão foi cancelada."
            case .timedOut: "O login no Google não foi concluído a tempo."
            case .denied(let reason): "O Google não autorizou: \(reason)"
            case .token(let reason): "Não foi possível concluir a conexão: \(reason)"
            case .api(let reason): "Não foi possível ler a agenda: \(reason)"
            }
        }
    }

    private struct Config: Decodable {
        let clientId: String
        let clientSecret: String
    }

    @Published private(set) var email = Settings.googleEmail
    @Published private(set) var events: [CalendarEvent] = []
    @Published private(set) var connecting = false
    @Published private(set) var error: String?

    var isConnected: Bool { Keychain.secret("google-calendar") != nil }

    private var accessToken: (value: String, expires: Date)?
    private var timer: Timer?

    private static let scope = "openid email https://www.googleapis.com/auth/calendar.readonly"

    /// From the app's Resources, or the repository's while developing (`swift run`).
    private static let config: Config? = {
        let bundled = Bundle.main.url(forResource: "google-oauth", withExtension: "json")
        let source = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
            .deletingLastPathComponent().appendingPathComponent("Resources/google-oauth.json")
        guard let data = try? Data(contentsOf: bundled ?? source),
              let config = try? JSONDecoder().decode(Config.self, from: data), !config.clientId.isEmpty else { return nil }
        return config
    }()

    init() {
        timer = Timer.scheduledTimer(withTimeInterval: 5 * 60, repeats: true) { [weak self] _ in
            Task { await self?.refresh() }
        }
        Task { await refresh() }
    }

    // MARK: - Connect

    func connect() async {
        guard !connecting else { return }
        error = nil
        guard let config = Self.config else {
            error = Failure.notConfigured.localizedDescription
            return
        }
        connecting = true
        defer { connecting = false }
        do {
            let verifier = Self.randomURLSafe(64)
            let challenge = Data(SHA256.hash(data: Data(verifier.utf8))).base64URLEncoded
            let state = Self.randomURLSafe(24)
            let receiver = try await LoopbackReceiver.start()
            let redirect = "http://127.0.0.1:\(receiver.port)"

            var authorize = URLComponents(string: "https://accounts.google.com/o/oauth2/v2/auth")!
            authorize.queryItems = [
                .init(name: "client_id", value: config.clientId),
                .init(name: "redirect_uri", value: redirect),
                .init(name: "response_type", value: "code"),
                .init(name: "scope", value: Self.scope),
                .init(name: "access_type", value: "offline"),
                .init(name: "prompt", value: "consent"),
                .init(name: "code_challenge", value: challenge),
                .init(name: "code_challenge_method", value: "S256"),
                .init(name: "state", value: state),
            ]
            NSWorkspace.shared.open(authorize.url!)

            let reply = try await receiver.waitForRedirect(timeout: 180)
            if let denied = reply["error"] { throw Failure.denied(denied) }
            guard reply["state"] == state, let code = reply["code"] else { throw Failure.token("resposta inesperada do Google") }

            let token = try await Self.tokenRequest([
                "code": code, "client_id": config.clientId, "client_secret": config.clientSecret,
                "redirect_uri": redirect, "grant_type": "authorization_code", "code_verifier": verifier,
            ])
            guard let refreshToken = token["refresh_token"] as? String else { throw Failure.token("o Google não devolveu acesso permanente") }
            Keychain.setSecret(refreshToken, for: "google-calendar")
            remember(token)
            let address = (token["id_token"] as? String).flatMap(Self.email(fromIDToken:))
            Settings.googleEmail = address
            email = address
            NSApp.activate(ignoringOtherApps: true)
            await refresh()
        } catch {
            self.error = error.localizedDescription
        }
    }

    func disconnect() {
        if let token = Keychain.secret("google-calendar") {
            var request = URLRequest(url: URL(string: "https://oauth2.googleapis.com/revoke")!)
            request.httpMethod = "POST"
            request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
            request.httpBody = Self.form(["token": token])
            URLSession.shared.dataTask(with: request).resume()
        }
        Keychain.setSecret(nil, for: "google-calendar")
        Settings.googleEmail = nil
        email = nil
        accessToken = nil
        events = []
        error = nil
    }

    // MARK: - Events

    /// Events from yesterday to tomorrow; quiet when not connected.
    func refresh() async {
        guard isConnected else { return }
        do {
            let token = try await validAccessToken()
            let day = Calendar.current.startOfDay(for: Date())
            let iso = ISO8601DateFormatter()
            var url = URLComponents(string: "https://www.googleapis.com/calendar/v3/calendars/primary/events")!
            url.queryItems = [
                .init(name: "timeMin", value: iso.string(from: day.addingTimeInterval(-86_400))),
                .init(name: "timeMax", value: iso.string(from: day.addingTimeInterval(2 * 86_400))),
                .init(name: "singleEvents", value: "true"),
                .init(name: "orderBy", value: "startTime"),
                .init(name: "maxResults", value: "100"),
            ]
            var request = URLRequest(url: url.url!)
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
            let (data, response) = try await URLSession.shared.data(for: request)
            let json = try JSONSerialization.jsonObject(with: data) as? [String: Any]
            guard (response as? HTTPURLResponse)?.statusCode == 200 else {
                throw Failure.api(((json?["error"] as? [String: Any])?["message"] as? String) ?? "erro do Google")
            }
            events = ((json?["items"] as? [[String: Any]]) ?? []).compactMap(Self.event)
            error = nil
        } catch {
            self.error = error.localizedDescription
        }
    }

    private static func event(_ item: [String: Any]) -> CalendarEvent? {
        guard item["status"] as? String != "cancelled",
              let start = ((item["start"] as? [String: Any])?["dateTime"] as? String).flatMap(parseDate),
              let end = ((item["end"] as? [String: Any])?["dateTime"] as? String).flatMap(parseDate) else { return nil }
        let attendees = ((item["attendees"] as? [[String: Any]]) ?? [])
            .filter { $0["self"] as? Bool != true && $0["resource"] as? Bool != true }
            .compactMap { person -> String? in
                if let name = person["displayName"] as? String, !name.isEmpty { return name }
                return (person["email"] as? String)?.components(separatedBy: "@").first
            }
        let video = (((item["conferenceData"] as? [String: Any])?["entryPoints"] as? [[String: Any]]) ?? [])
            .first { $0["entryPointType"] as? String == "video" }?["uri"] as? String
        return CalendarEvent(title: item["summary"] as? String ?? "Reunião", start: start, end: end,
                             attendees: attendees, link: item["hangoutLink"] as? String ?? video)
    }

    private static func parseDate(_ text: String) -> Date? {
        let formatter = ISO8601DateFormatter()
        if let date = formatter.date(from: text) { return date }
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter.date(from: text)
    }

    // MARK: - Tokens

    private func validAccessToken() async throws -> String {
        if let token = accessToken, token.expires > Date().addingTimeInterval(60) { return token.value }
        guard let config = Self.config, let refreshToken = Keychain.secret("google-calendar") else { throw Failure.notConfigured }
        let token: [String: Any]
        do {
            token = try await Self.tokenRequest([
                "refresh_token": refreshToken, "client_id": config.clientId, "client_secret": config.clientSecret,
                "grant_type": "refresh_token",
            ])
        } catch Failure.token(let reason) where reason.contains("invalid_grant") || reason.lowercased().contains("revoked")
                                              || reason.lowercased().contains("expired") {
            // Access revoked in the Google account (or expired): forget it and ask to connect again.
            Keychain.setSecret(nil, for: "google-calendar")
            accessToken = nil
            events = []
            throw Failure.token("o acesso à agenda expirou; conecte o Google de novo")
        }
        remember(token)
        guard let value = accessToken?.value else { throw Failure.token("sem acesso") }
        return value
    }

    private func remember(_ token: [String: Any]) {
        guard let value = token["access_token"] as? String else { return }
        let lifetime = (token["expires_in"] as? Double) ?? 3600
        accessToken = (value, Date().addingTimeInterval(lifetime))
    }

    private static func tokenRequest(_ fields: [String: String]) async throws -> [String: Any] {
        var request = URLRequest(url: URL(string: "https://oauth2.googleapis.com/token")!)
        request.httpMethod = "POST"
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        request.httpBody = form(fields)
        let (data, response) = try await URLSession.shared.data(for: request)
        let json = (try? JSONSerialization.jsonObject(with: data) as? [String: Any]) ?? [:]
        guard (response as? HTTPURLResponse)?.statusCode == 200 else {
            let code = json["error"] as? String ?? ""
            let description = json["error_description"] as? String ?? "erro do Google"
            throw Failure.token(code.isEmpty ? description : "\(description) (\(code))")
        }
        return json
    }

    private static func form(_ fields: [String: String]) -> Data {
        var allowed = CharacterSet.alphanumerics
        allowed.insert(charactersIn: "-._~")
        return Data(fields.map { "\($0.key)=\($0.value.addingPercentEncoding(withAllowedCharacters: allowed) ?? "")" }
            .joined(separator: "&").utf8)
    }

    private static func email(fromIDToken token: String) -> String? {
        let parts = token.split(separator: ".")
        guard parts.count > 1 else { return nil }
        var payload = String(parts[1]).replacingOccurrences(of: "-", with: "+").replacingOccurrences(of: "_", with: "/")
        while payload.count % 4 != 0 { payload += "=" }
        guard let data = Data(base64Encoded: payload),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return nil }
        return json["email"] as? String
    }

    private static func randomURLSafe(_ length: Int) -> String {
        let alphabet = Array("ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-._~")
        return String((0..<length).map { _ in alphabet[Int.random(in: 0..<alphabet.count)] })
    }
}

/// A one-request web server on 127.0.0.1 that receives the browser's redirect from Google.
private final class LoopbackReceiver: @unchecked Sendable {
    let port: UInt16
    private let listener: NWListener
    private let queue = DispatchQueue(label: "co.bkdg.bkdict.oauth")
    private var continuation: CheckedContinuation<[String: String], Error>?
    /// A redirect that arrived before anyone waited for it.
    private var early: Result<[String: String], Error>?

    private init(listener: NWListener, port: UInt16) {
        self.listener = listener
        self.port = port
    }

    static func start() async throws -> LoopbackReceiver {
        let parameters = NWParameters.tcp
        parameters.requiredLocalEndpoint = .hostPort(host: "127.0.0.1", port: .any)
        let listener = try NWListener(using: parameters)
        let queue = DispatchQueue(label: "co.bkdg.bkdict.oauth.start")
        // The state callbacks all run on `queue`, one at a time; the flag only stops a second resume.
        final class Once: @unchecked Sendable { var done = false }
        let once = Once()
        let port: UInt16 = try await withCheckedThrowingContinuation { continuation in
            listener.stateUpdateHandler = { state in
                guard !once.done else { return }
                switch state {
                case .ready:
                    once.done = true
                    continuation.resume(returning: listener.port?.rawValue ?? 0)
                case .failed(let error):
                    once.done = true
                    continuation.resume(throwing: error)
                default:
                    break
                }
            }
            listener.newConnectionHandler = { $0.cancel() }
            listener.start(queue: queue)
        }
        let receiver = LoopbackReceiver(listener: listener, port: port)
        listener.newConnectionHandler = { [weak receiver] connection in receiver?.handle(connection) }
        return receiver
    }

    /// The redirect's query parameters (code and state, or error).
    func waitForRedirect(timeout: TimeInterval) async throws -> [String: String] {
        defer { listener.cancel() }
        return try await withCheckedThrowingContinuation { continuation in
            queue.sync {
                if let early { continuation.resume(with: early) } else { self.continuation = continuation }
            }
            queue.asyncAfter(deadline: .now() + timeout) { [weak self] in
                self?.finish(.failure(GoogleCalendar.Failure.timedOut))
            }
        }
    }

    private func handle(_ connection: NWConnection) {
        connection.start(queue: queue)
        connection.receive(minimumIncompleteLength: 1, maximumLength: 64 * 1024) { [weak self] data, _, _, _ in
            let request = data.map { String(decoding: $0, as: UTF8.self) } ?? ""
            // "GET /?code=…&state=… HTTP/1.1"; anything else (a favicon) gets a 404.
            guard let target = request.split(separator: " ").dropFirst().first,
                  let components = URLComponents(string: "http://127.0.0.1\(target)"),
                  let items = components.queryItems, !items.isEmpty else {
                connection.send(content: Data("HTTP/1.1 404 Not Found\r\nContent-Length: 0\r\nConnection: close\r\n\r\n".utf8),
                                completion: .contentProcessed { _ in connection.cancel() })
                return
            }
            let ok = items.contains { $0.name == "code" }
            let page = """
            <!doctype html><html lang="pt-BR"><meta charset="utf-8"><title>Bkdict</title>
            <body style="margin:0;height:100vh;display:grid;place-items:center;background:#0A0A0A;color:#F1ECE2;font:16px -apple-system,'Segoe UI',sans-serif">
            <div style="text-align:center"><div style="font:600 22px Georgia,serif;margin-bottom:8px">\(ok ? "Pronto, Google Agenda conectado." : "A conexão não foi autorizada.")</div>
            <div style="opacity:.7">Pode fechar esta aba e voltar ao Bkdict.</div></div></body></html>
            """
            let body = Data(page.utf8)
            let head = "HTTP/1.1 200 OK\r\nContent-Type: text/html; charset=utf-8\r\nContent-Length: \(body.count)\r\nConnection: close\r\n\r\n"
            connection.send(content: Data(head.utf8) + body, completion: .contentProcessed { _ in connection.cancel() })
            var values: [String: String] = [:]
            for item in items { values[item.name] = item.value ?? "" }
            self?.finish(.success(values))
        }
    }

    private func finish(_ result: Result<[String: String], Error>) {
        guard let continuation else {
            if early == nil { early = result }
            return
        }
        self.continuation = nil
        continuation.resume(with: result)
    }
}

private extension Data {
    var base64URLEncoded: String {
        base64EncodedString().replacingOccurrences(of: "+", with: "-").replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }
}
