import Foundation
import Security

// Base URL of the deployed Fastify API on Railway.
// Set this to your Railway public domain once deployed.
let API_BASE_URL = ProcessInfo.processInfo.environment["API_BASE_URL"]
    ?? "https://your-app.up.railway.app"

// MARK: — Models

struct Schedule: Codable, Identifiable {
    let id: String
    var name: String
    var isActive: Bool
    var daysOfWeek: [Int]   // 1=Sun … 7=Sat
    var startTime: String   // "HH:MM:SS"
    var endTime: String
    var timezone: String
    var pomodoroEnabled: Bool
    var workMinutes: Int
    var shortBreakMin: Int
    var longBreakMin: Int
    var sessionsBeforeLongBreak: Int
    var createdAt: String
    var updatedAt: String

    enum CodingKeys: String, CodingKey {
        case id, name, timezone
        case isActive = "is_active"
        case daysOfWeek = "days_of_week"
        case startTime = "start_time"
        case endTime = "end_time"
        case pomodoroEnabled = "pomodoro_enabled"
        case workMinutes = "work_minutes"
        case shortBreakMin = "short_break_min"
        case longBreakMin = "long_break_min"
        case sessionsBeforeLongBreak = "sessions_before_long_break"
        case createdAt = "created_at"
        case updatedAt = "updated_at"
    }
}

struct BlockedApps: Codable {
    var scheduleId: String
    var iosActivitySelection: String?   // base64 FamilyActivitySelection
    var blockedDomains: [String]

    enum CodingKeys: String, CodingKey {
        case scheduleId = "schedule_id"
        case iosActivitySelection = "ios_activity_selection"
        case blockedDomains = "blocked_domains"
    }
}

// MARK: — Keychain helpers

private enum Keychain {
    static let service = "com.focusguard.jwt"

    static func save(token: String) {
        let data = Data(token.utf8)
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecValueData as String: data,
        ]
        SecItemDelete(query as CFDictionary)
        SecItemAdd(query as CFDictionary, nil)
    }

    static func load() -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecMatchLimit as String: kSecMatchLimitOne,
            kSecReturnData as String: true,
        ]
        var result: AnyObject?
        SecItemCopyMatching(query as CFDictionary, &result)
        guard let data = result as? Data else { return nil }
        return String(data: data, encoding: .utf8)
    }

    static func delete() {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
        ]
        SecItemDelete(query as CFDictionary)
    }
}

// MARK: — API client

enum APIError: Error {
    case noToken
    case httpError(Int)
    case decodingError(Error)
}

@MainActor
class APIClient: ObservableObject {
    static let shared = APIClient()

    @Published var isAuthenticated = false
    private var token: String? { Keychain.load() }

    init() {
        isAuthenticated = token != nil
    }

    // Called after Apple Sign In succeeds on device.
    // Sends Apple's identity token to our backend and stores the returned JWT.
    func signInWithApple(identityToken: String) async throws {
        struct Body: Encodable { let identityToken: String }
        struct Response: Decodable { let token: String }

        let response: Response = try await post(
            path: "/auth/apple",
            body: Body(identityToken: identityToken),
            authenticated: false
        )
        Keychain.save(token: response.token)
        isAuthenticated = true
    }

    func signOut() {
        Keychain.delete()
        isAuthenticated = false
    }

    // MARK: — Schedules

    func fetchSchedules() async throws -> [Schedule] {
        try await get(path: "/schedules")
    }

    func createSchedule(_ schedule: NewSchedule) async throws -> Schedule {
        try await post(path: "/schedules", body: schedule)
    }

    func updateSchedule(id: String, _ updates: ScheduleUpdate) async throws -> Schedule {
        try await put(path: "/schedules/\(id)", body: updates)
    }

    func deleteSchedule(id: String) async throws {
        try await delete(path: "/schedules/\(id)")
    }

    func fetchBlockedApps(scheduleId: String) async throws -> BlockedApps {
        try await get(path: "/schedules/\(scheduleId)/apps")
    }

    func updateBlockedApps(scheduleId: String, iosActivitySelection: String?, blockedDomains: [String]) async throws -> BlockedApps {
        struct Body: Encodable {
            let iosActivitySelection: String?
            let blockedDomains: [String]
            enum CodingKeys: String, CodingKey {
                case iosActivitySelection = "ios_activity_selection"
                case blockedDomains = "blocked_domains"
            }
        }
        return try await put(
            path: "/schedules/\(scheduleId)/apps",
            body: Body(iosActivitySelection: iosActivitySelection, blockedDomains: blockedDomains)
        )
    }

    // MARK: — HTTP primitives

    private func request<T: Decodable>(
        method: String,
        path: String,
        body: (any Encodable)? = nil,
        authenticated: Bool = true
    ) async throws -> T {
        var url = URLComponents(string: "\(API_BASE_URL)\(path)")!
        var req = URLRequest(url: url.url!)
        req.httpMethod = method
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")

        if authenticated {
            guard let t = token else { throw APIError.noToken }
            req.setValue("Bearer \(t)", forHTTPHeaderField: "Authorization")
        }

        if let body {
            req.httpBody = try JSONEncoder().encode(body)
        }

        let (data, response) = try await URLSession.shared.data(for: req)
        let status = (response as! HTTPURLResponse).statusCode
        guard (200..<300).contains(status) else { throw APIError.httpError(status) }

        do {
            return try JSONDecoder().decode(T.self, from: data)
        } catch {
            throw APIError.decodingError(error)
        }
    }

    private func get<T: Decodable>(path: String, authenticated: Bool = true) async throws -> T {
        try await request(method: "GET", path: path, authenticated: authenticated)
    }

    private func post<T: Decodable>(path: String, body: some Encodable, authenticated: Bool = true) async throws -> T {
        try await request(method: "POST", path: path, body: body, authenticated: authenticated)
    }

    private func put<T: Decodable>(path: String, body: some Encodable) async throws -> T {
        try await request(method: "PUT", path: path, body: body)
    }

    private func delete(path: String) async throws {
        var req = URLRequest(url: URL(string: "\(API_BASE_URL)\(path)")!)
        req.httpMethod = "DELETE"
        guard let t = token else { throw APIError.noToken }
        req.setValue("Bearer \(t)", forHTTPHeaderField: "Authorization")
        let (_, response) = try await URLSession.shared.data(for: req)
        let status = (response as! HTTPURLResponse).statusCode
        guard (200..<300).contains(status) else { throw APIError.httpError(status) }
    }
}

// MARK: — Input types (separate from the full Schedule model for cleaner API calls)

struct NewSchedule: Encodable {
    var name: String
    var isActive: Bool = true
    var daysOfWeek: [Int]
    var startTime: String
    var endTime: String
    var timezone: String
    var pomodoroEnabled: Bool = false
    var workMinutes: Int = 25
    var shortBreakMin: Int = 5
    var longBreakMin: Int = 15
    var sessionsBeforeLongBreak: Int = 4

    enum CodingKeys: String, CodingKey {
        case name, timezone
        case isActive = "is_active"
        case daysOfWeek = "days_of_week"
        case startTime = "start_time"
        case endTime = "end_time"
        case pomodoroEnabled = "pomodoro_enabled"
        case workMinutes = "work_minutes"
        case shortBreakMin = "short_break_min"
        case longBreakMin = "long_break_min"
        case sessionsBeforeLongBreak = "sessions_before_long_break"
    }
}

struct ScheduleUpdate: Encodable {
    var name: String?
    var isActive: Bool?
    var daysOfWeek: [Int]?
    var startTime: String?
    var endTime: String?
    var timezone: String?
    var pomodoroEnabled: Bool?
    var workMinutes: Int?
    var shortBreakMin: Int?
    var longBreakMin: Int?
    var sessionsBeforeLongBreak: Int?

    enum CodingKeys: String, CodingKey {
        case name, timezone
        case isActive = "is_active"
        case daysOfWeek = "days_of_week"
        case startTime = "start_time"
        case endTime = "end_time"
        case pomodoroEnabled = "pomodoro_enabled"
        case workMinutes = "work_minutes"
        case shortBreakMin = "short_break_min"
        case longBreakMin = "long_break_min"
        case sessionsBeforeLongBreak = "sessions_before_long_break"
    }
}
