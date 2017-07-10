/* This Source Code Form is subject to the terms of the Mozilla Public License, v. 2.0. If a copy of the MPL was not distributed with this file, You can obtain one at http://mozilla.org/MPL/2.0/. */

import Foundation
import XCTest
@testable import Client
import Shared

class SyncTest: XCTestCase {
    
    override func setUp() {
        // Clear CD
    }
    
    func testSync() {
        expectationForNotification(NotificationSyncReady, object: nil, handler:nil)
        
        let sync = Sync.shared
        waitForExpectations(timeout: 15) { error in
            XCTAssertNil(error, "Error timeout waiting sync ready")
        }
        
        if !sync.checkIsSyncReady() {
            XCTAssert(false, "Sync not fully initialized")
            return;
        }
        
        // TODO: Implement below

        var bm = "[{ action: \(SyncActions.create.rawValue),"
        bm += "deviceId: [ 0 ]," +
            "objectId: [ 171, 177, 210, 122, 73, 79, 129, 2, 30, 151, 125, 139, 226, 96, 92, 144 ]," +
            "bookmark:" +
              "{ site:" +
                "{ location: 'https://www.google.com/'," +
                "title: 'Google'," +
                "customTitle: ''," +
                "lastAccessedTime: 1486066976216," +
                "creationTime: 4 }," +
                "isFolder: false," +
                "parentFolderObjectId: undefined } }]"
        
        let syncbm = SyncBookmark(json: JSON(string:bm))
        let realbm = Bookmark.add(rootObject: syncbm, save: true, sendToSync: true)

        sleep(5)
        
        let fetchExpect = expectation(description: "Fetch result expectation")
        sync.fetch() { error in
            XCTAssertNil(error, "Fetching had result error")
            fetchExpect.fulfill()
        }

        waitForExpectations(timeout: 4) { (error:NSError?) -> Void in
            XCTAssertNil(error, "Fetching had expectation error")
        } as! XCWaitCompletionHandler as! XCWaitCompletionHandler as! XCWaitCompletionHandler as! XCWaitCompletionHandler as! XCWaitCompletionHandler as! XCWaitCompletionHandler
        
        // TODO: Somehow need to check the fetched results

    }

}
