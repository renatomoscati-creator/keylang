import XCTest
@testable import StudyKit

final class TranslatorTests: XCTestCase {

    func testUnavailableReportsWhyRatherThanPretending() async {
        let translator = UnavailableTranslator()
        XCTAssertFalse(translator.isAvailable)
        do {
            _ = try await translator.translate("Quiero un vaso de agua")
            XCTFail("an unavailable translator returned a translation")
        } catch let error as TranslatorError {
            // The message goes on screen under the sentence. It has to say what
            // to do about it, because "no pack yet" is the state the app is in
            // the first time it is ever opened.
            guard case .unavailable(let why) = error else { return XCTFail("wrong case") }
            XCTAssertFalse(why.isEmpty)
        } catch {
            XCTFail("unexpected error \(error)")
        }
    }

    func testCannedTranslatorRoundTrips() async throws {
        let translator = CannedTranslator(["Quiero un vaso de agua": "I want a glass of water"])
        XCTAssertTrue(translator.isAvailable)
        let out = try await translator.translate("Quiero un vaso de agua")
        XCTAssertEqual(out, "I want a glass of water")
    }
}
