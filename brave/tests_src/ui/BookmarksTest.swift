/* This Source Code Form is subject to the terms of the Mozilla Public License, v. 2.0. If a copy of the MPL was not distributed with this file, You can obtain one at http://mozilla.org/MPL/2.0/. */

import Foundation
import XCTest

class BookmarksTest: XCTestCase {

    fileprivate func openBookmarks() {
        let app = XCUIApplication()
        let bookmarksAndHistoryPanelButton = app.buttons["Bookmarks and History Panel"]
        bookmarksAndHistoryPanelButton.tap()
        
        app.scrollViews.otherElements.buttons["Show Bookmarks"].tap()
    }
    
    fileprivate func addGoogleAsFirstBookmark() {
        let app = XCUIApplication()
        UITestUtils.loadSite(app, "www.google.com")
        openBookmarks()

        let bmCount = app.tables.element.cells.count
        app.scrollViews.otherElements.buttons["Add Bookmark"].tap()
        XCTAssert(app.tables.element.cells.count > bmCount)
    }
    
    // Requries bookmark page being open
    fileprivate func createFolder(_ title: String) {
        let app = XCUIApplication()
        let toolbarsQuery = app.scrollViews.otherElements.toolbars
        toolbarsQuery.buttons["Edit"].tap()
        toolbarsQuery.buttons["New Folder"].tap()
        
        let collectionViewsQuery = app.alerts["New Folder"].collectionViews
        collectionViewsQuery.textFields["<folder name>"].typeText("Foo")
        app.buttons["OK"].tap()
        // Stay in edit mode
    }

    func testAddDeleteBookmark() {
        UITestUtils.restart(["BRAVE-DELETE-BOOKMARKS"])
        let app = XCUIApplication()

        addGoogleAsFirstBookmark()

        let bookmarksAndHistoryPanelButton = app.buttons["Bookmarks and History Panel"]
        let elementsQuery = app.scrollViews.otherElements

        // close panel
        //app.otherElements["webViewContainer"].tap()
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
        let toolbarsQuery = elementsQuery.toolbars
        toolbarsQuery.buttons["Edit"].tap()
        let bmCount = app.tables.element.cells.count
        app.scrollViews.otherElements.tables["SiteTable"].buttons["Delete Google"].tap()
        app.scrollViews.otherElements.tables["SiteTable"].buttons["Delete"].tap()
        XCTAssert(app.tables.element.cells.count < bmCount)
        toolbarsQuery.buttons["Done"].tap()
        elementsQuery.navigationBars["Bookmarks"].staticTexts["Bookmarks"].tap()
        elementsQuery.tables["SiteTable"].tap()

        // close the panel
        app.coordinate(withNormalizedOffset: CGVector(dx: UIScreen.main.bounds.width, dy:  UIScreen.main.bounds.height)).tap()
    }


    func testFolderNav() {
        UITestUtils.restart(["BRAVE-DELETE-BOOKMARKS"])
        addGoogleAsFirstBookmark()
        createFolder("Foo")
        
        let app = XCUIApplication()
        let elementsQuery = app.scrollViews.otherElements
        let toolbarsQuery = elementsQuery.toolbars
    
        elementsQuery.tables["SiteTable"].staticTexts["Google"].tap()
        elementsQuery.tables.staticTexts["Root Folder"].tap()
        app.pickerWheels.element(boundBy: 0).adjust(toPickerWheelValue: "Foo")
        elementsQuery.navigationBars["Bookmarks"].buttons["Bookmarks"].tap()

        XCTAssert(app.scrollViews.otherElements.tables["SiteTable"].cells.count == 1)

        toolbarsQuery.buttons["Done"].tap()

        elementsQuery.tables["SiteTable"].staticTexts["Foo"].tap()
        toolbarsQuery.buttons["Edit"].tap()
        elementsQuery.tables["SiteTable"].staticTexts["Google"].tap()

        // close the panel (bug #448)
        app.coordinate(withNormalizedOffset: CGVector(dx: UIScreen.main.bounds.width, dy:  UIScreen.main.bounds.height)).tap()
    }
    
    func testBookmarkNameEncoding() {
        UITestUtils.restart(["BRAVE-DELETE-BOOKMARKS"])
        let app = XCUIApplication()
        
        addGoogleAsFirstBookmark()

        let elementsQuery = app.scrollViews.otherElements
        let toolbarsQuery = elementsQuery.toolbars
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
        UITestUtils.restart(["BRAVE-DELETE-BOOKMARKS"])
        let app = XCUIApplication()
        let elementsQuery = app.scrollViews.otherElements
        let toolbarsQuery = elementsQuery.toolbars
        let name = "Foo"
        
        UITestUtils.loadSite(app, "www.google.com")
        
        openBookmarks()
        createFolder(name)
        
        toolbarsQuery.buttons["Done"].tap()
        elementsQuery.tables["SiteTable"].staticTexts[name].tap()

        XCTAssertEqual(app.tables.element.cells.count, 0)
        app.scrollViews.otherElements.buttons["Add Bookmark"].tap()
        XCTAssertEqual(app.tables.element.cells.count, 1)
        
        elementsQuery.navigationBars[name].buttons["Bookmarks"].tap()
        
        // Should only be Foo
        XCTAssertEqual(app.scrollViews.otherElements.tables["SiteTable"].cells.count, 1)
    }
}
