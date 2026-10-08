import XCTest
@testable import MeetingFollowup

final class MeetingModelTests: XCTestCase {
    func testOldRecordWithoutCheckpointStillLoads() throws {
        let meeting = Meeting(title: "Buyer call", audioFile: "audio.m4a")
        let data = try JSONEncoder().encode(meeting)
        var object = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        object.removeValue(forKey: "transcriptionCheckpoint")
        let restored = try JSONDecoder().decode(Meeting.self, from: JSONSerialization.data(withJSONObject: object))
        XCTAssertNil(restored.transcriptionCheckpoint)
        XCTAssertEqual(restored.title, "Buyer call")
    }

    func testCheckpointSurvivesSaveWithoutReplacingEditedTranscript() throws {
        var meeting = Meeting(title: "Buyer call", audioFile: "audio.m4a")
        meeting.transcript = "Manually corrected price: USD 0.48."
        meeting.transcriptionCheckpoint = TranscriptionCheckpoint(completedParts: 1, totalParts: 3,
            text: "First part", segments: [Segment(start: 12, end: 14, text: "First part")])
        let restored = try JSONDecoder().decode(Meeting.self, from: JSONEncoder().encode(meeting))
        XCTAssertEqual(restored.transcript, meeting.transcript)
        XCTAssertEqual(restored.transcriptionCheckpoint?.completedParts, 1)
        XCTAssertEqual(restored.transcriptionCheckpoint?.segments.first?.start, 12)
    }

    func testEditedTranscriptFlagsOldSummaryAndExport() {
        var meeting = Meeting(title: "Buyer call", audioFile: "audio.m4a")
        meeting.transcript = "USD 0.48"
        meeting.summarySource = "USD 0.84"
        XCTAssertTrue(meeting.summaryIsStale)
        XCTAssertTrue(meeting.exportSummary.contains("文字稿已修改"))
        XCTAssertTrue(meeting.exportText.contains("USD 0.48"))
        XCTAssertFalse(meeting.exportText.contains("USD 0.84"))
    }

    func testExportDoesNotPretendSuggestedTaskIsConfirmed() {
        var meeting = Meeting(title: "Buyer call", audioFile: "audio.m4a")
        meeting.tasks = [FollowUp(title: "Send samples", evidence: "Please send samples.")]
        XCTAssertTrue(meeting.exportSummary.contains("待人工确认"))
        XCTAssertTrue(meeting.exportSummary.contains("负责人：未明确"))
        XCTAssertTrue(meeting.exportSummary.contains("截止：未明确"))
        XCTAssertTrue(meeting.exportSummary.contains("Please send samples."))
    }
}
