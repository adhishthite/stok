// Copyright 2026 Adhish Thite
// SPDX-License-Identifier: Apache-2.0

import XCTest

@testable import StokEngine

final class RESTResponseTests: XCTestCase {
  func testMalformedResponseDoesNotExposeItsContents() {
    XCTAssertThrowsError(try RESTResponse.decode(Data("Private fixture response".utf8))) {
      XCTAssertFalse($0.localizedDescription.contains("Private fixture"))
      XCTAssertEqual(($0 as NSError).code, -5)
    }
  }

  func testProviderErrorsKeepStatusWithoutCopyingPrivateMessage() throws {
    let data = try JSONSerialization.data(withJSONObject: [
      "error": ["code": "invalid_api_key_error", "message": "Private fixture response"]
    ])
    XCTAssertThrowsError(try RESTResponse.decode(data, status: 403)) {
      XCTAssertEqual(($0 as NSError).code, 403)
      XCTAssertTrue($0.localizedDescription.contains("Stok Settings"))
      XCTAssertFalse($0.localizedDescription.contains("Private fixture"))
    }
  }

  func testSuccessfulEnvelopePassesThroughUnchanged() throws {
    let data = try JSONSerialization.data(withJSONObject: ["transcript": "Hello"])
    let decoded = try RESTResponse.decode(data)
    XCTAssertEqual(decoded["transcript"] as? String, "Hello")
    for code in [400, 401, 403, 404] {
      XCTAssertTrue(RESTResponse.error(code: code).localizedDescription.contains("Stok Settings"))
    }
    // The engine shows errors from this domain verbatim, so they must carry it.
    XCTAssertEqual(RESTResponse.error(code: 500).domain, "SarvamAPI")
  }
}
