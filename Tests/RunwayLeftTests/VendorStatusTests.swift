import XCTest
@testable import RunwayLeft

final class VendorStatusTests: XCTestCase {
    // Trimmed from a real status.claude.com/api/v2/summary.json response.
    // Note: this page sends `group: false` / `only_show_if_degraded: false`.
    private let claudeOperational = """
    {
      "page": {"id": "abc", "name": "Claude", "url": "https://status.claude.com", "time_zone": "Etc/UTC", "updated_at": "2026-09-03T08:00:00.000Z"},
      "components": [
        {"id": "c1", "name": "claude.ai", "status": "operational", "created_at": "2024-01-01T00:00:00.000Z", "updated_at": "2026-09-01T00:00:00.000Z", "position": 1, "description": null, "showcase": false, "start_date": null, "group_id": null, "page_id": "abc", "group": false, "only_show_if_degraded": false},
        {"id": "c2", "name": "Claude Console (platform.claude.com)", "status": "operational", "group": false, "only_show_if_degraded": false},
        {"id": "c3", "name": "Claude API (api.anthropic.com)", "status": "operational", "group": false, "only_show_if_degraded": false},
        {"id": "c4", "name": "Claude Code", "status": "operational", "group": false, "only_show_if_degraded": false},
        {"id": "c5", "name": "Claude Cowork", "status": "operational", "group": false, "only_show_if_degraded": false},
        {"id": "c6", "name": "Claude for Government", "status": "operational", "group": false, "only_show_if_degraded": false}
      ],
      "incidents": [],
      "scheduled_maintenances": [],
      "status": {"indicator": "none", "description": "All Systems Operational"}
    }
    """

    // Trimmed from a real status.openai.com/api/v2/summary.json response.
    // Note: this page sends `group: null` / `only_show_if_degraded: null`.
    private let openaiOperational = """
    {
      "page": {"id": "xyz", "name": "OpenAI", "url": "https://status.openai.com/"},
      "components": [
        {"id": "o1", "name": "Images", "status": "operational", "group": null, "group_id": null, "only_show_if_degraded": null},
        {"id": "o2", "name": "Responses", "status": "operational", "group": null, "only_show_if_degraded": null},
        {"id": "o3", "name": "Codex Web", "status": "operational", "group": null, "only_show_if_degraded": null},
        {"id": "o4", "name": "Codex in ChatGPT Desktop", "status": "operational", "group": null, "only_show_if_degraded": null},
        {"id": "o5", "name": "Codex API", "status": "operational", "group": null, "only_show_if_degraded": null},
        {"id": "o6", "name": "VS Code extension", "status": "operational", "group": null, "only_show_if_degraded": null},
        {"id": "o7", "name": "Chat Completions", "status": "operational", "group": null, "only_show_if_degraded": null}
      ],
      "incidents": [],
      "scheduled_maintenances": [],
      "status": {"indicator": "none", "description": "All Systems Operational"}
    }
    """

    // Synthetic degraded variant: relevant component in partial outage, an
    // unrelated component degraded, an unknown status string, an open incident
    // with updates, and a resolved incident that must be filtered out.
    private let claudeDegraded = """
    {
      "page": {"id": "abc", "name": "Claude", "url": "https://status.claude.com"},
      "components": [
        {"id": "c1", "name": "claude.ai", "status": "degraded_performance", "group": false},
        {"id": "c3", "name": "Claude API (api.anthropic.com)", "status": "operational", "group": false},
        {"id": "c4", "name": "Claude Code", "status": "partial_outage", "group": false},
        {"id": "c9", "name": "Future Thing", "status": "some_new_state_we_do_not_know", "group": false},
        {"id": "g1", "name": "A Group Row", "status": "major_outage", "group": true}
      ],
      "incidents": [
        {
          "id": "i1", "name": "Elevated errors on Claude Code", "status": "investigating", "impact": "major",
          "shortlink": "https://stspg.io/abc", "created_at": "2026-09-03T07:30:00.000Z", "updated_at": "2026-09-03T07:45:00.000Z",
          "incident_updates": [
            {"id": "u2", "status": "investigating", "body": "We are continuing to investigate.", "updated_at": "2026-09-03T07:45:00.000Z"},
            {"id": "u1", "status": "investigating", "body": "We are looking into it.", "updated_at": "2026-09-03T07:30:00.000Z"}
          ]
        },
        {"id": "i0", "name": "Old thing", "status": "resolved", "impact": "minor"}
      ],
      "scheduled_maintenances": [
        {"id": "m1", "name": "Database upgrade", "status": "scheduled", "impact": "maintenance", "scheduled_for": "2026-09-05T02:00:00.000Z", "scheduled_until": "2026-09-05T04:00:00.000Z"}
      ],
      "status": {"indicator": "major", "description": "Partial System Outage"}
    }
    """

    private func parse(_ json: String, vendor: StatusVendor) throws -> VendorStatus {
        try VendorStatusService.parse(Data(json.utf8), vendor: vendor, fetchedAt: Date())
    }

    func testClaudeOperationalPayloadDecodesAndPicksRelevantComponents() throws {
        let status = try parse(claudeOperational, vendor: .claude)

        XCTAssertTrue(status.isLoaded)
        XCTAssertEqual(status.indicator, .none)
        XCTAssertEqual(status.description, "All Systems Operational")
        XCTAssertEqual(status.components.count, 6)
        XCTAssertEqual(status.relevantComponents.map { $0.name }, ["Claude API (api.anthropic.com)", "Claude Code"])
        XCTAssertEqual(status.effectiveLevel, .operational)
        XCTAssertEqual(status.headline, "All systems go")
        XCTAssertTrue(status.affectedComponents.isEmpty)
        XCTAssertTrue(status.activeIncidents.isEmpty)
    }

    func testOpenAIPayloadWithNullGroupFieldsDecodes() throws {
        let status = try parse(openaiOperational, vendor: .openai)

        XCTAssertTrue(status.isLoaded)
        XCTAssertEqual(status.components.count, 7)
        XCTAssertEqual(
            Set(status.relevantComponents.map { $0.name }),
            ["Codex Web", "Codex in ChatGPT Desktop", "Codex API", "VS Code extension"]
        )
        XCTAssertEqual(status.effectiveLevel, .operational)
    }

    func testDegradedPayloadSurfacesWorstRelevantComponentAndIncidents() throws {
        let status = try parse(claudeDegraded, vendor: .claude)

        XCTAssertEqual(status.indicator, .major)
        XCTAssertEqual(status.effectiveLevel, .partialOutage, "Claude Code partial outage should win over the operational API")
        XCTAssertEqual(status.headline, "Partial outage")
        XCTAssertTrue(status.effectiveLevel.isProblem)

        // Group rows are excluded; unknown status strings decode without failing.
        XCTAssertFalse(status.affectedComponents.contains { $0.name == "A Group Row" })
        XCTAssertEqual(status.components.first { $0.name == "Future Thing" }?.status, .unknown)

        XCTAssertEqual(status.otherAffectedComponents.map { $0.name }, ["claude.ai", "Future Thing"])

        XCTAssertEqual(status.activeIncidents.count, 1)
        let incident = try XCTUnwrap(status.activeIncidents.first)
        XCTAssertEqual(incident.name, "Elevated errors on Claude Code")
        XCTAssertEqual(incident.impactLevel, .partialOutage)
        XCTAssertEqual(incident.latestUpdate?.body, "We are continuing to investigate.")
        XCTAssertEqual(incident.link?.absoluteString, "https://stspg.io/abc")

        XCTAssertEqual(status.maintenances.count, 1)
        XCTAssertNotNil(VendorStatusService.parseDate(status.maintenances[0].scheduledFor))
    }

    func testMissingComponentsFallBackToPageIndicator() throws {
        let json = """
        {"page": {"name": "Claude"}, "status": {"indicator": "minor", "description": "Minor issues"}}
        """
        let status = try parse(json, vendor: .claude)

        XCTAssertTrue(status.isLoaded)
        XCTAssertTrue(status.relevantComponents.isEmpty)
        XCTAssertEqual(status.effectiveLevel, .degraded)
        XCTAssertEqual(status.headline, "Degraded")
    }

    func testUnknownIndicatorDoesNotThrow() throws {
        let json = """
        {"status": {"indicator": "purple", "description": "?"}, "components": []}
        """
        let status = try parse(json, vendor: .openai)
        XCTAssertEqual(status.indicator, .unknown)
        XCTAssertEqual(status.effectiveLevel, .unknown)
        XCTAssertFalse(status.effectiveLevel.isProblem)
    }

    func testMalformedPayloadThrows() {
        XCTAssertThrowsError(try parse("not json at all", vendor: .claude))
    }

    func testUnloadedStatusReportsCheckingOrUnavailable() {
        var status = VendorStatus(vendor: .claude)
        XCTAssertFalse(status.isLoaded)
        XCTAssertEqual(status.headline, "Checking…")
        XCTAssertEqual(status.effectiveLevel, .unknown)

        status.fetchedAt = Date()
        status.errorMessage = "The Internet connection appears to be offline."
        XCTAssertFalse(status.isLoaded)
        XCTAssertEqual(status.headline, "Status unavailable")
    }

    func testStatusLevelOrdering() {
        XCTAssertLessThan(StatusLevel.operational, StatusLevel.degraded)
        XCTAssertLessThan(StatusLevel.degraded, StatusLevel.partialOutage)
        XCTAssertLessThan(StatusLevel.partialOutage, StatusLevel.majorOutage)
        XCTAssertFalse(StatusLevel.maintenance.isProblem)
        XCTAssertTrue(StatusLevel.degraded.isProblem)
    }
}
