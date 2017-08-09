/* This Source Code Form is subject to the terms of the Mozilla Public License, v. 2.0. If a copy of the MPL was not distributed with this file, You can obtain one at http://mozilla.org/MPL/2.0/. */

import Foundation
import XCTest
@testable import Client
import Shared

class NicewareTest: XCTestCase {
    
    func testSplitBytes() {
        let split = Niceware().splitBytes(fromJoinedBytes: "00ee4a423aa3a30f595fc200fa6ad9c96338bb020c375b9298e7687984bae19f")
        XCTAssertNotNil(split)
        
        guard let split2 = split else { return }
        
        XCTAssertEqual(split2, [0x00, 0xee, 0x4a, 0x42, 0x3a, 0xa3, 0xa3, 0x0f, 0x59, 0x5f, 0xc2, 0x00, 0xfa, 0x6a, 0xd9, 0xc9, 0x63, 0x38, 0xbb, 0x02, 0x0c, 0x37, 0x5b, 0x92, 0x98, 0xe7, 0x68, 0x79, 0x84, 0xba, 0xe1, 0x9f])
    }
    
    func testNewByteSeed() {
        let niceware = Niceware()
        let byteCount = 8
        let expect = self.expectation(description: "newPassphrase attempt")
        
        niceware.uniqueBytes(count: byteCount) { (result, error) in
            XCTAssertNil(error, "new passphrase contained error")
            XCTAssertNotNil(result, "new passphrase result was nil")
            // Force unwrapping only okay since this is a unit test
            XCTAssertEqual(result!.count, byteCount)
            
            expect.fulfill()
        }
        
        self.waitForExpectations(timeout: 4) { error in
            XCTAssertNil(error, "Niceware new passphrase error")
        }
    }
    
    func testPassphraseToByte() {
        let niceware = Niceware()
        
        let expect = self.expectation(description: "passphraseToByte attempt")

        let input = ["administrational","experimental","disconnection","plane","gigaton","savaging","wheaten","suez","herman","retina","bailment","gorier","overmodestly","idealism","mesa","theurgy",]
        let expectedOut = [0x00, 0xee, 0x4a, 0x42, 0x3a, 0xa3, 0xa3, 0x0f, 0x59, 0x5f, 0xc2, 0x00, 0xfa, 0x6a, 0xd9, 0xc9, 0x63, 0x38, 0xbb, 0x02, 0x0c, 0x37, 0x5b, 0x92, 0x98, 0xe7, 0x68, 0x79, 0x84, 0xba, 0xe1, 0x9f]
        
        niceware.bytes(fromPassphrase: input) { (result, error) in
            XCTAssertNil(error, "passphraseToByte contained error")
            XCTAssertNotNil(result, "passphraseToByte result was nil")
            
            guard let result = result else {
                XCTAssertNotNil(false, "passphrase cast to [String] failed")
                return
            }
            
            XCTAssertEqual(result, expectedOut)
            
            expect.fulfill()
        }
        
        self.waitForExpectations(timeout: 4) { error in
            XCTAssertNil(error, "Niceware error with `bytes`")
        }
        
    }
    
    func testByteToPassphrase() {
        let niceware = Niceware()
        
        let expect = self.expectation(description: "byteToPassphrase attempt")
        niceware.passphrase(fromBytes: [0x00, 0xee, 0x4a, 0x42, 0x3a, 0xa3, 0xa3, 0x0f, 0x59, 0x5f, 0xc2, 0x00, 0xfa, 0x6a, 0xd9, 0xc9, 0x63, 0x38, 0xbb, 0x02, 0x0c, 0x37, 0x5b, 0x92, 0x98, 0xe7, 0x68, 0x79, 0x84, 0xba, 0xe1, 0x9f]) { (result, error) in
            XCTAssertNil(error, "byteToPassphrase contained error")
            XCTAssertNotNil(result, "byteToPassphrase result was nil")
            
            guard let resultWithStrings = result else { return }
            
            XCTAssertEqual(resultWithStrings, ["administrational","experimental","disconnection","plane","gigaton","savaging","wheaten","suez","herman","retina","bailment","gorier","overmodestly","idealism","mesa","theurgy",])
            
            expect.fulfill()
        }
        
        self.waitForExpectations(timeout: 4) { error in
            XCTAssertNil(error, "Niceware error with `passphrase`")
        }
    }
}
