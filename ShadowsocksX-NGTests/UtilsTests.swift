//
//  UtilsTests.swift
//  ShadowsocksX-NG
//
//  Created by Rainux Luo on 07/01/2017.
//  Copyright © 2017 qiuyuzhou. All rights reserved.
//

import XCTest
@testable import ShadowsocksX_NG

class UtilsTests: XCTestCase {

    override func setUp() {
        super.setUp()
        // Put setup code here. This method is called before the invocation of each test method in the class.
    }

    override func tearDown() {
        // Put teardown code here. This method is called after the invocation of each test method in the class.
        super.tearDown()
    }

    func testParseSSURLwithPlainURL() {
        let url = URL(string: "ss://aes-256-cfb:password@example.com:8388")

        let profile = ParseSSURL(url)

        XCTAssertNotNil(profile)

        XCTAssertEqual(profile?["ServerHost"] as? String, "example.com")
        XCTAssertEqual(profile?["ServerPort"] as? UInt16, 8388)
        XCTAssertEqual(profile?["Method"] as? String, "aes-256-cfb")
        XCTAssertEqual(profile?["Password"] as? String, "password")
    }

    func testParseSSURLwithPlainURLandQuery() {
        let url = URL(string: "ss://aes-256-cfb:password@example.com:8388?Remark=Prism&OTA=true")

        let profile = ParseSSURL(url)

        XCTAssertNotNil(profile)

        XCTAssertEqual(profile?["ServerHost"] as? String, "example.com")
        XCTAssertEqual(profile?["ServerPort"] as? UInt16, 8388)
        XCTAssertEqual(profile?["Method"] as? String, "aes-256-cfb")
        XCTAssertEqual(profile?["Password"] as? String, "password")
        XCTAssertEqual(profile?["Remark"] as? String, "Prism")
        XCTAssertEqual(profile?["OTA"] as? Bool, true)
    }

    func testParseSSURLwithPlainURLandAnotherQuery() {
        let url = URL(string: "ss://aes-256-cfb:password@example.com:8388?Remark=Prism&OTA=0")

        let profile = ParseSSURL(url)

        XCTAssertNotNil(profile)

        XCTAssertEqual(profile?["ServerHost"] as? String, "example.com")
        XCTAssertEqual(profile?["ServerPort"] as? UInt16, 8388)
        XCTAssertEqual(profile?["Method"] as? String, "aes-256-cfb")
        XCTAssertEqual(profile?["Password"] as? String, "password")
        XCTAssertEqual(profile?["Remark"] as? String, "Prism")
        XCTAssertEqual(profile?["OTA"] as? Bool, false)
    }

    func testParseSSURLwithBase64EncodedURL() {
        // "ss://aes-256-cfb:password@example.com:8388"
        let url = URL(string: "ss://YWVzLTI1Ni1jZmI6cGFzc3dvcmRAZXhhbXBsZS5jb206ODM4OA")

        let profile = ParseSSURL(url)

        XCTAssertNotNil(profile)

        XCTAssertEqual(profile?["ServerHost"] as? String, "example.com")
        XCTAssertEqual(profile?["ServerPort"] as? UInt16, 8388)
        XCTAssertEqual(profile?["Method"] as? String, "aes-256-cfb")
        XCTAssertEqual(profile?["Password"] as? String, "password")
    }

    func testParseSSURLwithBase64EncodedURLandQuery() {
        // "ss://aes-256-cfb:password@example.com:8388?Remark=Prism&OTA=true"
        let url = URL(string: "ss://YWVzLTI1Ni1jZmI6cGFzc3dvcmRAZXhhbXBsZS5jb206ODM4OD9SZW1hcms9UHJpc20mT1RBPXRydWU")

        let profile = ParseSSURL(url)

        XCTAssertNotNil(profile)

        XCTAssertEqual(profile?["ServerHost"] as? String, "example.com")
        XCTAssertEqual(profile?["ServerPort"] as? UInt16, 8388)
        XCTAssertEqual(profile?["Method"] as? String, "aes-256-cfb")
        XCTAssertEqual(profile?["Password"] as? String, "password")
        XCTAssertEqual(profile?["Remark"] as? String, "Prism")
        XCTAssertEqual(profile?["OTA"] as? Bool, true)
    }

    func testParseSSURLwithEmptyURL() {
        let url = URL(string: "ss://")

        let profile = ParseSSURL(url)

        XCTAssertNil(profile)
    }

    func testParseSSURLwithInvalidURL() {
        let url = URL(string: "ss://invalid url")

        let profile = ParseSSURL(url)

        XCTAssertNil(profile)
    }

    func testParseSSURLwithBase64EncodedInvalidURL() {
        // "ss://invalid url"
        let url = URL(string: "ss://aW52YWxpZCB1cmw")

        let profile = ParseSSURL(url)

        XCTAssertNil(profile)
    }

    func testPerformanceExample() {
        // This is an example of a performance test case.
        self.measure {
            // Put the code you want to measure the time of here.
        }
    }

}
