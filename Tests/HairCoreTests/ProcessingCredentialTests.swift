import XCTest
@testable import HairCore

final class ProcessingCredentialTests: XCTestCase {
    func testEndpointCanonicalizationAndCredentialValidation() throws {
        XCTAssertEqual(try ProcessingEndpoint.origin(URL(string: "https://EXAMPLE.com:443/")!).absoluteString, "https://example.com")
        for text in ["http://example.com", "https://user:password@example.com", "https://example.com/path", "https://example.com?token=x"] {
            XCTAssertThrowsError(try ProcessingEndpoint.origin(URL(string: text)!))
        }
        XCTAssertThrowsError(try GuestCredential(owner: UUID().uuidString, token: String(repeating: "a", count: 32)+"\r\n"))
        XCTAssertThrowsError(try GuestCredential(owner: "not-an-owner", token: String(repeating: "a", count: 43)))
    }
}
