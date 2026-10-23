import Foundation

enum CodexQuotaMappingError: Error {
  case invalidResponse
  case missingQuotaWindow
}

enum CodexQuotaMapper {
  static func snapshot(from data: Data, now: Date = Date()) throws -> QuotaSnapshot {
    let response: RateLimitsResponse
    do {
      response = try JSONDecoder().decode(RateLimitsResponse.self, from: data)
    } catch {
      throw CodexQuotaMappingError.invalidResponse
    }

    let selectedLimits = response.rateLimitsByLimitId?["codex"] ?? response.rateLimits
    guard let selectedLimits else {
      throw CodexQuotaMappingError.missingQuotaWindow
    }

    let windows = [
      makeWindow(id: "primary", from: selectedLimits.primary),
      makeWindow(id: "secondary", from: selectedLimits.secondary),
    ].compactMap { $0 }

    guard !windows.isEmpty else {
      throw CodexQuotaMappingError.missingQuotaWindow
    }

    let resetCredits = response.rateLimitResetCredits.map { summary in
      QuotaResetCredits(
        availableCount: summary.availableCount,
        credits: summary.credits?.map { credit in
          QuotaResetCredit(
            expirationDate: credit.expiresAt.map {
              Date(timeIntervalSince1970: TimeInterval($0))
            }
          )
        }
      )
    }

    return QuotaSnapshot(
      windows: windows,
      resetCredits: resetCredits,
      lastUpdated: now
    )
  }

  private static func makeWindow(
    id: String,
    from value: RateLimitWindow?
  ) -> QuotaWindow? {
    guard let value else {
      return nil
    }
    return QuotaWindow(
      id: id,
      usedPercentage: value.usedPercent,
      resetDate: Date(timeIntervalSince1970: TimeInterval(value.resetsAt)),
      windowDurationMinutes: value.windowDurationMins ?? 0
    )
  }
}

private struct RateLimitsResponse: Decodable {
  let rateLimits: RateLimitSnapshot?
  let rateLimitsByLimitId: [String: RateLimitSnapshot]?
  let rateLimitResetCredits: ResetCreditsSummary?
}

private struct RateLimitSnapshot: Decodable {
  let primary: RateLimitWindow?
  let secondary: RateLimitWindow?
}

private struct RateLimitWindow: Decodable {
  let usedPercent: Double
  let windowDurationMins: Int?
  let resetsAt: Int64
}

private struct ResetCreditsSummary: Decodable {
  let availableCount: Int
  let credits: [ResetCredit]?
}

private struct ResetCredit: Decodable {
  let expiresAt: Int64?
}
