//
//  ServerProfileTests.swift
//  ShadowsocksX-NG
//
//  Created by Rainux Luo on 07/01/2017.
//  Copyright © 2017 qiuyuzhou. All rights reserved.
//

import XCTest
@testable import ShadowsocksX_NG

class ServerProfileTests: XCTestCase {

    // "ss://aes-256-cfb:password@example.com:8388"
    let profileUrl = URL(string: "ss://YWVzLTI1Ni1jZmI6cGFzc3dvcmRAZXhhbXBsZS5jb206ODM4OA")

    // "ss://aes-256-cfb:password@example.com:8388?Remark=Prism&OTA=true"
    let profileFullUrl = URL(string: "ss://YWVzLTI1Ni1jZmI6cGFzc3dvcmRAZXhhbXBsZS5jb206ODM4OD9SZW1hcms9UHJpc20mT1RBPXRydWU")

    var profile: ServerProfile!

    override func setUp() {
        super.setUp()

        profile = ServerProfile.fromDictionary(["ServerHost": "example.com",
                                                "ServerPort": 8388,
                                                "Method": "aes-256-cfb",
                                                "Password": "password",
                                                "Remark": "Protoss Prism",
                                                "OTA": true])
        XCTAssertNotNil(profile)
    }

    override func tearDown() {
        // Put teardown code here. This method is called after the invocation of each test method in the class.
        super.tearDown()
    }

    func testServerProfileURL() {
        let parsed = ParseSSURL(profile.URL())

        XCTAssertNotNil(parsed)

        XCTAssertEqual(parsed?["ServerHost"] as? String, profile.serverHost)
        XCTAssertEqual(parsed?["ServerPort"] as? UInt16, profile.serverPort)
        XCTAssertEqual(parsed?["Method"] as? String, profile.method)
        XCTAssertEqual(parsed?["Password"] as? String, profile.password)
        XCTAssertEqual(parsed?["Remark"] as? String, profile.remark)
        XCTAssertEqual(parsed?["OTA"] as? Bool, profile.ota)
    }

    func testPerformanceExample() {
        // This is an example of a performance test case.
        self.measure {
            // Put the code you want to measure the time of here.
        }
    }

}
