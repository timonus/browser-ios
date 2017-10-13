/* This Source Code Form is subject to the terms of the Mozilla Public License, v. 2.0. If a copy of the MPL was not distributed with this file, You can obtain one at http://mozilla.org/MPL/2.0/. */

import Foundation
import XCTest

class BookmarksTest: XCTestCase {
    var app: XCUIApplication!
    var elementsQuery: XCUIElementQuery!
    var toolbarsQuery: XCUIElementQuery!
    
    override func setUp() {
        super.setUp()
        app = XCUIApplication()
        UITestUtils.restart(["BRAVE-DELETE-BOOKMARKS"])
        elementsQuery = app.scrollViews.otherElements
        toolbarsQuery = elementsQuery.toolbars
    }
    
    override func tearDown() {
        super.tearDown()
        app = nil
        elementsQuery = nil
        toolbarsQuery = nil
    }

    fileprivate func openBookmarks() {
        let bookmarksAndHistoryPanelButton = app.buttons["Bookmarks and History Panel"]
        bookmarksAndHistoryPanelButton.tap()
        
        app.scrollViews.otherElements.buttons["Show Bookmarks"].tap()
    }
    
    fileprivate func addGoogleAsFirstBookmark() {
        UITestUtils.loadSite(app, "www.google.ca")
        openBookmarks()

        let bmCount = app.tables.element.cells.count
        app.scrollViews.otherElements.buttons["Add Bookmark"].tap()
        XCTAssert(app.tables.element.cells.count > bmCount)
    }
    
    // Requries bookmark page being open
    fileprivate func createFolder(_ title: String) {
        toolbarsQuery.buttons["New Folder"].tap()
        
        let newFolderAlert = app.alerts["New Folder"]
        newFolderAlert.collectionViews.textFields["Name"].typeText(title)
        newFolderAlert.buttons["OK"].tap()
    }

    func testAddDeleteBookmark() {
        addGoogleAsFirstBookmark()

        let bookmarksAndHistoryPanelButton = app.buttons["Bookmarks and History Panel"]

        // close panel
        app.coordinate(withNormalizedOffset: CGVector(dx: UIScreen.main.bounds.width, dy:  UIScreen.main.bounds.height)).tap()

        // switch sites
        UITestUtils.loadSite(app, "www.example.com")

        bookmarksAndHistoryPanelButton.tap()

        // load google from bookmarks
        let googleStaticText = app.scrollViews.otherElements.tables["SiteTable"].staticTexts["Google"]
        googleStaticText.tap()

        UITestUtils.waitForGooglePageLoad(self)
        
        // delete the bookmark
        bookmarksAndHistoryPanelButton.tap()
        toolbarsQuery.buttons["Edit"].tap()
        let bmCount = app.tables.element.cells.count
        app.scrollViews.otherElements.tables["SiteTable"].buttons["Delete Google"].tap()
        app.scrollViews.otherElements.tables["SiteTable"].buttons["Delete"].tap()
        XCTAssert(app.tables.element.cells.count < bmCount)
        toolbarsQuery.buttons["Done"].tap()
        
        // close the panel
        app.coordinate(withNormalizedOffset: CGVector(dx: UIScreen.main.bounds.width, dy:  UIScreen.main.bounds.height)).tap()
    }

    func testClosePanelWhileEditing() {
        // Test for issue #448
        addGoogleAsFirstBookmark()
        createFolder("Foo")
        
        toolbarsQuery.buttons["Edit"].tap()
        elementsQuery.tables["SiteTable"].staticTexts["Google"].tap()
        
        // Tap on webview to hide panel
        app.coordinate(withNormalizedOffset: CGVector(dx: UIScreen.main.bounds.width, dy:  UIScreen.main.bounds.height)).tap()
        
        // Open bookmark panel again to verify everything is ok
        app.buttons["Bookmarks and History Panel"].tap()
        XCTAssert(app.scrollViews.otherElements.tables["SiteTable"].cells.count == 2)
        // After reopening, bookmark panel shouldn't be in edit state, for edit state 'Done' button is in place of 'Edit'.
        XCTAssert(toolbarsQuery.buttons["Edit"].exists)
    }
    
    func testBookmarkNameEncoding() {
        addGoogleAsFirstBookmark()

        let googleText = "Google"
        let testingText = " Te'sti\"ng"
        
        toolbarsQuery.buttons["Edit"].tap()
        
        elementsQuery.tables["SiteTable"].staticTexts[googleText].tap()
        elementsQuery.tables.staticTexts["Name"].tap()
        app.typeText(testingText)
        
        elementsQuery.navigationBars["Bookmarks"].buttons["Bookmarks"].tap()
        toolbarsQuery.buttons["Done"].tap()

        // Make sure single item (didn't duplicate)
        XCTAssertEqual(app.scrollViews.otherElements.tables["SiteTable"].cells.count, 1)
        XCTAssertTrue(elementsQuery.tables["SiteTable"].staticTexts[googleText + testingText].exists)
    }
    
    func testAddingBookmarkToFolder() {
        let name = "Foo"
        
        UITestUtils.loadSite(app, "www.google.com")
        
        openBookmarks()
        createFolder(name)
        
        elementsQuery.tables["SiteTable"].staticTexts[name].tap()

        XCTAssertEqual(app.tables.element.cells.count, 0)
        app.scrollViews.otherElements.buttons["Add Bookmark"].tap()
        XCTAssertEqual(app.tables.element.cells.count, 1)
        
        elementsQuery.navigationBars[name].buttons["Bookmarks"].tap()
        
        // Should only be Foo
        XCTAssertEqual(app.scrollViews.otherElements.tables["SiteTable"].cells.count, 1)
    }
}
