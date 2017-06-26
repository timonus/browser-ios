/* This Source Code Form is subject to the terms of the Mozilla Public License, v. 2.0. If a copy of the MPL was not distributed with this file, You can obtain one at http://mozilla.org/MPL/2.0/. */

import Shared

extension BrowserViewController {
    func reloadTab(){
        if homePanelController == nil {
            tabManager.selectedTab?.reload()
        }
    }

    func goBack(){
        if tabManager.selectedTab?.canGoBack == true && homePanelController == nil {
            tabManager.selectedTab?.goBack()
        }
    }
    func goForward(){
        if tabManager.selectedTab?.canGoForward == true && homePanelController == nil {
            tabManager.selectedTab?.goForward()
        }
    }

    func findOnPage(){
        if let tab = tabManager.selectedTab, homePanelController == nil {
            browser(tab, didSelectFindInPageForSelection: "")
        }
    }

    func selectLocationBar() {
        urlBar.browserLocationViewDidTapLocation(urlBar.locationView)
    }

    func newTab() {
        openBlankNewTabAndFocus(isPrivate: PrivateBrowsing.singleton.isOn)
        postAsyncToMain(0.2) {
            self.selectLocationBar()
        }
    }

    func newPrivateTab() {
        openBlankNewTabAndFocus(isPrivate: true)
        postAsyncToMain(0.2) {
            self.selectLocationBar()
        }
    }

    func closeTab() {
        guard let tab = tabManager.selectedTab else { return }
        let priv = tab.isPrivate
        nextOrPrevTabShortcut(false)
        tabManager.removeTab(tab, createTabIfNoneLeft: !priv)
        if priv && tabManager.tabs.privateTabs.count == 0 {
            urlBarDidPressTabs(urlBar)
        }
    }

    fileprivate func nextOrPrevTabShortcut(_ isNext: Bool) {
        guard let tab = tabManager.selectedTab else { return }
        let step = isNext ? 1 : -1
        let tabList: [Browser] = tabManager.tabs.displayedTabsForCurrentPrivateMode
        func wrappingMod(_ val:Int, mod:Int) -> Int {
            return ((val % mod) + mod) % mod
        }
        assert(wrappingMod(-1, mod: 10) == 9)
        let index = wrappingMod((tabList.index(of: tab)! + step), mod: tabList.count)
        tabManager.selectTab(tabList[index])
    }

    func nextTab() {
        nextOrPrevTabShortcut(true)
    }

    func previousTab() {
        nextOrPrevTabShortcut(false)
    }

    override var keyCommands: [UIKeyCommand]? {
        let result =  [
            UIKeyCommand(input: "r", modifierFlags: .command, action: #selector(BrowserViewController.reloadTab), discoverabilityTitle: Strings.ReloadPageTitle),
            UIKeyCommand(input: "[", modifierFlags: .command, action: #selector(BrowserViewController.goBack), discoverabilityTitle: Strings.BackTitle),
            UIKeyCommand(input: "]", modifierFlags: .command, action: #selector(BrowserViewController.goForward), discoverabilityTitle: Strings.ForwardTitle),

            UIKeyCommand(input: "f", modifierFlags: .command, action: #selector(BrowserViewController.findOnPage), discoverabilityTitle: Strings.FindTitle),
            UIKeyCommand(input: "l", modifierFlags: .command, action: #selector(BrowserViewController.selectLocationBar), discoverabilityTitle: Strings.SelectLocationBarTitle),
            UIKeyCommand(input: "t", modifierFlags: .command, action: #selector(BrowserViewController.newTab), discoverabilityTitle: Strings.NewTabTitle),
            //#if DEBUG
                UIKeyCommand(input: "t", modifierFlags: .control, action: #selector(BrowserViewController.newTab), discoverabilityTitle: Strings.NewTabTitle),
            //#endif
            UIKeyCommand(input: "p", modifierFlags: [.command, .shift], action: #selector(BrowserViewController.newPrivateTab), discoverabilityTitle: Strings.NewPrivateTabTitle),
            UIKeyCommand(input: "w", modifierFlags: .command, action: #selector(BrowserViewController.closeTab), discoverabilityTitle: Strings.CloseTabTitle),
            UIKeyCommand(input: "\t", modifierFlags: .control, action: #selector(BrowserViewController.nextTab), discoverabilityTitle: Strings.ShowNextTabTitle),
            UIKeyCommand(input: "\t", modifierFlags: [.control, .shift], action: #selector(BrowserViewController.previousTab), discoverabilityTitle: Strings.ShowPreviousTabTitle),
        ]
        #if DEBUG
            // in simulator, CMD+t is slow-mo animation
            return result + [
                UIKeyCommand(input: "t", modifierFlags: [.command, .Shift], action: #selector(BrowserViewController.newTab))]
        #else
            return result
        #endif
    }
}
