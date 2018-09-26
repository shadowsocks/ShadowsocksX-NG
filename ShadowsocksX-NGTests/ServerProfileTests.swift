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

    func testInitWithSelfGeneratedURL() {
        let newProfile = ServerProfile.init(url: profile.URL()!)

        XCTAssertEqual(newProfile?.serverHost, profile.serverHost)
        XCTAssertEqual(newProfile?.serverPort, profile.serverPort)
        XCTAssertEqual(newProfile?.method, profile.method)
        XCTAssertEqual(newProfile?.password, profile.password)
        XCTAssertEqual(newProfile?.remark, profile.remark)
    }

    func testInitWithPlainURL() {
        let url = URL(string: "ss://aes-256-cfb:password@example.com:8388")!

        let profile = ServerProfile(url: url)

        XCTAssertNotNil(profile)

        XCTAssertEqual(profile?.serverHost, "example.com")
        XCTAssertEqual(profile?.serverPort, 8388)
        XCTAssertEqual(profile?.method, "aes-256-cfb")
        XCTAssertEqual(profile?.password, "password")
        XCTAssertEqual(profile?.remark, "")
    }

    func testInitWithPlainURLandQuery() {
        let url = URL(string: "ss://aes-256-cfb:password@example.com:8388?Remark=Prism&OTA=true")!

        let profile = ServerProfile(url: url)

        XCTAssertNotNil(profile)

        XCTAssertEqual(profile?.serverHost, "example.com")
        XCTAssertEqual(profile?.serverPort, 8388)
        XCTAssertEqual(profile?.method, "aes-256-cfb")
        XCTAssertEqual(profile?.password, "password")
        XCTAssertEqual(profile?.remark, "Prism")
    }

    func testInitWithPlainURLandAnotherQuery() {
        let url = URL(string: "ss://aes-256-cfb:password@example.com:8388?Remark=Prism&OTA=0")!

        let profile = ServerProfile(url: url)

        XCTAssertNotNil(profile)

        XCTAssertEqual(profile?.serverHost, "example.com")
        XCTAssertEqual(profile?.serverPort, 8388)
        XCTAssertEqual(profile?.method, "aes-256-cfb")
        XCTAssertEqual(profile?.password, "password")
        XCTAssertEqual(profile?.remark, "Prism")
    }

    func testInitWithBase64EncodedURL() {
        // "ss://aes-256-cfb:password@example.com:8388"
        let url = URL(string: "ss://YWVzLTI1Ni1jZmI6cGFzc3dvcmRAZXhhbXBsZS5jb206ODM4OA")!

        let profile = ServerProfile(url: url)

        XCTAssertNotNil(profile)

        XCTAssertEqual(profile?.serverHost, "example.com")
        XCTAssertEqual(profile?.serverPort, 8388)
        XCTAssertEqual(profile?.method, "aes-256-cfb")
        XCTAssertEqual(profile?.password, "password")
        XCTAssertEqual(profile?.remark, "")
    }

    func testInitWithBase64EncodedURLandQuery() {
        // "ss://aes-256-cfb:password@example.com:8388?Remark=Prism&OTA=true"
        let url = URL(string: "ss://YWVzLTI1Ni1jZmI6cGFzc3dvcmRAZXhhbXBsZS5jb206ODM4OD9SZW1hcms9UHJpc20mT1RBPXRydWU")!

        let profile = ServerProfile(url: url)

        XCTAssertNotNil(profile)

        XCTAssertEqual(profile?.serverHost, "example.com")
        XCTAssertEqual(profile?.serverPort, 8388)
        XCTAssertEqual(profile?.method, "aes-256-cfb")
        XCTAssertEqual(profile?.password, "password")
        XCTAssertEqual(profile?.remark, "Prism")
    }
    
    func testInitWithLegacyBase64EncodedURLWithTag() {
        let url = URL(string: "ss://YmYtY2ZiOnRlc3RAMTkyLjE2OC4xMDAuMTo4ODg4Cg#example-server")!
        
        let profile = ServerProfile(url: url)
        
        XCTAssertNotNil(profile)
        XCTAssertEqual(profile?.remark, "example-server")
    }

    func testInitWithEmptyURL() {
        let url = URL(string: "ss://")!

        let profile = ServerProfile(url: url)

        XCTAssertNil(profile)
    }

    func testInitWithBase64EncodedInvalidURL() {
        // "ss://invalid url"
        let url = URL(string: "ss://aW52YWxpZCB1cmw")!

        let profile = ServerProfile(url: url)

        XCTAssertNil(profile)
    }

    func testInitWithSIP002URL() {
        // "ss://aes-256-cfb:password@example.com:8388?Remark=Prism&OTA=true"
        let url = URL(string: "ss://YWVzLTI1Ni1jZmI6cGFzc3dvcmQ=@example.com:8388/?Remark=Prism&OTA=true")!

        let profile = ServerProfile(url: url)

        XCTAssertNotNil(profile)

        XCTAssertEqual(profile?.serverHost, "example.com")
        XCTAssertEqual(profile?.serverPort, 8388)
        XCTAssertEqual(profile?.method, "aes-256-cfb")
        XCTAssertEqual(profile?.password, "password")
        XCTAssertEqual(profile?.remark, "Prism")
    }

    func testInitWithSIP002URLProfileName() {
        let url = URL(string: "ss://YWVzLTI1Ni1jZmI6cGFzc3dvcmQ=@example.com:8388/#Name")!

        let profile = ServerProfile(url: url)

        XCTAssertNotNil(profile)
        XCTAssertEqual(profile?.remark, "Name")
    }

    func testInitWithSIP002URLProfileNameOverride() {
        let url = URL(string: "ss://YWVzLTI1Ni1jZmI6cGFzc3dvcmQ=@example.com:8388/?Remark=Name#Overriden")!

        let profile = ServerProfile(url: url)

        XCTAssertNotNil(profile)
        XCTAssertEqual(profile?.remark, "Overriden")
    }

    func testPerformanceExample() {
        // This is an example of a performance test case.
        self.measure {
            // Put the code you want to measure the time of here.
        }
    }

}
