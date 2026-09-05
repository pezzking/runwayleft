import Foundation

/// Fetches the public Statuspage summary feeds for Anthropic and OpenAI.
///
/// This is the only network access in the app. It is read-only, sends no
/// identifying data, and can be switched off in Settings.
class VendorStatusService {
    static let shared = VendorStatusService()

    private let session: URLSession

    init(session: URLSession? = nil) {
        if let session = session {
            self.session = session
        } else {
            let config = URLSessionConfiguration.ephemeral
            config.timeoutIntervalForRequest = 10
            config.timeoutIntervalForResource = 15
            config.requestCachePolicy = .reloadIgnoringLocalCacheData
            config.httpAdditionalHeaders = ["Accept": "application/json"]
            self.session = URLSession(configuration: config)
        }
    }

    func fetch(_ vendor: StatusVendor, completion: @escaping (VendorStatus) -> Void) {
        var request = URLRequest(url: vendor.summaryURL)
        request.httpMethod = "GET"

        session.dataTask(with: request) { data, response, error in
            let now = Date()
            if let error = error {
                var failed = VendorStatus(vendor: vendor)
                failed.fetchedAt = now
                failed.errorMessage = error.localizedDescription
                completion(failed)
                return
            }

            if let http = response as? HTTPURLResponse, !(200...299).contains(http.statusCode) {
                var failed = VendorStatus(vendor: vendor)
                failed.fetchedAt = now
                failed.errorMessage = "HTTP \(http.statusCode)"
                completion(failed)
                return
            }

            guard let data = data else {
                var failed = VendorStatus(vendor: vendor)
                failed.fetchedAt = now
                failed.errorMessage = "Empty response"
                completion(failed)
                return
            }

            do {
                completion(try Self.parse(data, vendor: vendor, fetchedAt: now))
            } catch {
                var failed = VendorStatus(vendor: vendor)
                failed.fetchedAt = now
                failed.errorMessage = "Could not read status feed"
                completion(failed)
            }
        }.resume()
    }

    static func parse(_ data: Data, vendor: StatusVendor, fetchedAt: Date = Date()) throws -> VendorStatus {
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        let summary = try decoder.decode(StatusPageSummary.self, from: data)
        return VendorStatus(vendor: vendor, summary: summary, fetchedAt: fetchedAt)
    }

    // MARK: - Formatting helpers

    private static let isoWithFractional: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return f
    }()

    private static let isoPlain: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime]
        return f
    }()

    static func parseDate(_ raw: String?) -> Date? {
        guard let raw = raw, !raw.isEmpty else { return nil }
        return isoWithFractional.date(from: raw) ?? isoPlain.date(from: raw)
    }

    /// "Sep 3, 5:19 PM" style local rendering of a Statuspage timestamp.
    static func formatTimestamp(_ raw: String?) -> String? {
        guard let date = parseDate(raw) else { return nil }
        let f = DateFormatter()
        f.dateStyle = .medium
        f.timeStyle = .short
        f.doesRelativeDateFormatting = true
        return f.string(from: date)
    }
}
