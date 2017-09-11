/* This Source Code Form is subject to the terms of the Mozilla Public
 * License, v. 2.0. If a copy of the MPL was not distributed with this
 * file, You can obtain one at http://mozilla.org/MPL/2.0/. */

import UIKit

class TrayToBrowserAnimator: NSObject, UIViewControllerAnimatedTransitioning {
    func animateTransition(using transitionContext: UIViewControllerContextTransitioning) {
      guard let vc = transitionContext.viewController(forKey: UITransitionContextViewControllerKey.to) else { return }
      guard let bvc = (vc as? BraveTopViewController)?.browserViewController else { return }
      guard let tabTray = transitionContext.viewController(forKey: UITransitionContextViewControllerKey.from) as? TabTrayController else { return }
      transitionFromTray(tabTray, toBrowser: bvc, usingContext: transitionContext)
    }

    func transitionDuration(using transitionContext: UIViewControllerContextTransitioning?) -> TimeInterval {
        return 0.4
    }
}

private extension TrayToBrowserAnimator {
    func transitionFromTray(_ tabTray: TabTrayController, toBrowser bvc: BrowserViewController, usingContext transitionContext: UIViewControllerContextTransitioning) {
        let container = transitionContext.containerView
        guard let selectedTab = bvc.tabManager.selectedTab else { return }

        // Bug 1205464 - Top Sites tiles blow up or shrink after rotating
        // Force the BVC's frame to match the tab trays since for some reason on iOS 9 the UILayoutContainer in
        // the UINavigationController doesn't rotate the presenting view controller
        let os = ProcessInfo().operatingSystemVersion
        switch (os.majorVersion, os.minorVersion, os.patchVersion) {
        case (9, _, _):
            bvc.view.frame = UIWindow().frame
        default:
            break
        }

        let tabManager = bvc.tabManager
        let displayedTabs = tabManager.tabs.displayedTabsForCurrentPrivateMode
        guard let expandFromIndex = displayedTabs.index(of: selectedTab) else { return }

        // Hide browser components
        bvc.toggleSnackBarVisibility(false)
        toggleWebViewVisibility(false, usingTabManager: bvc.tabManager)
        bvc.homePanelController?.view.isHidden = true
        bvc.webViewContainerBackdrop.isHidden = true

        // Take a snapshot of the collection view that we can scale/fade out. We don't need to wait for screen updates since it's already rendered on the screen
        guard let tabCollectionViewSnapshot = tabTray.collectionView.snapshotView(afterScreenUpdates: false) else { return }
        tabTray.collectionView.alpha = 0
        tabCollectionViewSnapshot.frame = tabTray.collectionView.frame
        container.insertSubview(tabCollectionViewSnapshot, aboveSubview: tabTray.view)

        // Create a fake cell to use for the upscaling animation
        let startingFrame = calculateCollapsedCellFrameUsingCollectionView(tabTray.collectionView, atIndex: expandFromIndex)
        let cell = createTransitionCellFromBrowser(bvc.tabManager.selectedTab, withFrame: startingFrame)
        cell.backgroundHolder.layer.cornerRadius = 0

        container.insertSubview(getApp().rootViewController.topViewController!.view, aboveSubview: tabCollectionViewSnapshot)
        container.insertSubview(cell, aboveSubview: bvc.view)

        // Flush any pending layout/animation code in preperation of the animation call
        container.layoutIfNeeded()


        let finalFrame = calculateExpandedCellFrameFromBVC(bvc)
        bvc.footer.alpha = shouldDisplayFooterForBVC(bvc) ? 1 : 0
        bvc.urlBar.isTransitioning = true

        // Re-calculate the starting transforms for header/footer views in case we switch orientation
        resetTransformsForViews([bvc.header, bvc.footer, bvc.footerBackdrop])
        transformHeaderFooterForBVC(bvc, toFrame: startingFrame, container: container)

        UIView.animate(withDuration: self.transitionDuration(using: transitionContext),
            delay: 0, usingSpringWithDamping: 1,
            initialSpringVelocity: 0,
            options: UIViewAnimationOptions(),
            animations:
        {
            // Scale up the cell and reset the transforms for the header/footers
            cell.frame = finalFrame
            container.layoutIfNeeded()
            cell.titleWrapper.transform = CGAffineTransform(translationX: 0, y: -cell.titleWrapper.frame.height)

            bvc.tabTrayDidDismiss(tabTray)

            tabCollectionViewSnapshot.transform = CGAffineTransform(scaleX: 0.9, y: 0.9)
            tabCollectionViewSnapshot.alpha = 0

            // Push out the navigation bar buttons
            let buttonOffset = tabTray.addTabButton.frame.width + TabTrayControllerUX.ToolbarButtonOffset
            tabTray.addTabButton.transform = CGAffineTransform.identity.translatedBy(x: buttonOffset , y: 0)
#if !BRAVE
            tabTray.settingsButton.transform = CGAffineTransform.identity.translatedBy(x: -buttonOffset , y: 0)
            tabTray.togglePrivateMode.transform = CGAffineTransform.identity.translatedBy(x: buttonOffset , y: 0)
#endif
        }, completion: { finished in
            // Remove any of the views we used for the animation
            cell.removeFromSuperview()
            tabCollectionViewSnapshot.removeFromSuperview()
            bvc.footer.alpha = 1
            bvc.toggleSnackBarVisibility(true)
            toggleWebViewVisibility(true, usingTabManager: bvc.tabManager)
            bvc.webViewContainerBackdrop.isHidden = false
            bvc.homePanelController?.view.isHidden = false
            bvc.urlBar.isTransitioning = false
            transitionContext.completeTransition(true)
        })
    }
}

class BrowserToTrayAnimator: NSObject, UIViewControllerAnimatedTransitioning {
    func animateTransition(using transitionContext: UIViewControllerContextTransitioning) {
      guard let vc = transitionContext.viewController(forKey: UITransitionContextViewControllerKey.from) else { return }
      guard let bvc = (vc as? BraveTopViewController)?.browserViewController else { return }
      guard let tabTray = transitionContext.viewController(forKey: UITransitionContextViewControllerKey.to) as? TabTrayController else { return }
      transitionFromBrowser(bvc, toTabTray: tabTray, usingContext: transitionContext)
    }

    func transitionDuration(using transitionContext: UIViewControllerContextTransitioning?) -> TimeInterval {
        return 0.4
    }
}

private extension BrowserToTrayAnimator {
    func transitionFromBrowser(_ bvc: BrowserViewController, toTabTray tabTray: TabTrayController, usingContext transitionContext: UIViewControllerContextTransitioning) {

        let container = transitionContext.containerView
        guard let selectedTab = bvc.tabManager.selectedTab else { return }

        let tabManager = bvc.tabManager
        let displayedTabs = tabManager.tabs.displayedTabsForCurrentPrivateMode
        guard let scrollToIndex = displayedTabs.index(of: selectedTab) else { return }

        // Insert tab tray below the browser and force a layout so the collection view can get it's frame right
        container.insertSubview(tabTray.view, belowSubview: bvc.view)

        // Force subview layout on the collection view so we can calculate the correct end frame for the animation
        tabTray.view.layoutSubviews()

        tabTray.collectionView.scrollToItem(at: IndexPath(item: scrollToIndex, section: 0), at: .centeredVertically, animated: false)

        // Build a tab cell that we will use to animate the scaling of the browser to the tab
        let expandedFrame = calculateExpandedCellFrameFromBVC(bvc)

        let cell = createTransitionCellFromBrowser(bvc.tabManager.selectedTab, withFrame: expandedFrame)
        cell.backgroundHolder.layer.cornerRadius = TabTrayControllerUX.CornerRadius

        // Take a snapshot of the collection view to perform the scaling/alpha effect
        let tabCollectionViewSnapshot = tabTray.collectionView.snapshotView(afterScreenUpdates: true)
        tabCollectionViewSnapshot!.frame = tabTray.collectionView.frame
        tabCollectionViewSnapshot!.transform = CGAffineTransform(scaleX: 0.9, y: 0.9)
        tabCollectionViewSnapshot!.alpha = 0
        tabTray.view.addSubview(tabCollectionViewSnapshot!)

        container.addSubview(cell)
        cell.layoutIfNeeded()
        cell.titleWrapper.transform = CGAffineTransform(translationX: 0, y: -cell.titleWrapper.frame.size.height)

        // Hide views we don't want to show during the animation in the BVC
        bvc.homePanelController?.view.isHidden = true
        bvc.toggleSnackBarVisibility(false)
        toggleWebViewVisibility(false, usingTabManager: bvc.tabManager)
        bvc.urlBar.isTransitioning = true

        // Since we are hiding the collection view and the snapshot API takes the snapshot after the next screen update,
        // the screenshot ends up being blank unless we set the collection view hidden after the screen update happens. 
        // To work around this, we dispatch the setting of collection view to hidden after the screen update is completed.
        DispatchQueue.main.async {
            tabTray.collectionView.isHidden = true
            let finalFrame = calculateCollapsedCellFrameUsingCollectionView(tabTray.collectionView,
                atIndex: scrollToIndex)

            UIView.animate(withDuration: self.transitionDuration(using: transitionContext),
                delay: 0, usingSpringWithDamping: 1,
                initialSpringVelocity: 0,
                options: UIViewAnimationOptions(),
                animations:
            {
                cell.frame = finalFrame
                cell.titleWrapper.transform = CGAffineTransform.identity
                cell.layoutIfNeeded()

                transformHeaderFooterForBVC(bvc, toFrame: finalFrame, container: container)

                bvc.urlBar.updateAlphaForSubviews(0)
                bvc.footer.alpha = 0
                tabCollectionViewSnapshot!.alpha = 1

                var viewsToReset: [UIView?] = [tabCollectionViewSnapshot, tabTray.addTabButton]
#if !BRAVE
                viewsToReset.append(tabTray.togglePrivateMode)
#endif
                resetTransformsForViews(viewsToReset)
            }, completion: { finished in
                // Remove any of the views we used for the animation
                cell.removeFromSuperview()
                tabCollectionViewSnapshot!.removeFromSuperview()
                tabTray.collectionView.isHidden = false

                bvc.toggleSnackBarVisibility(true)
                toggleWebViewVisibility(true, usingTabManager: bvc.tabManager)
                bvc.homePanelController?.view.isHidden = false

                bvc.urlBar.isTransitioning = false
                transitionContext.completeTransition(true)
            })
        }
    }
}

private func transformHeaderFooterForBVC(_ bvc: BrowserViewController, toFrame finalFrame: CGRect, container: UIView) {
    let footerForTransform = footerTransform(bvc.footer.frame, toFrame: finalFrame, container: container)
    let headerForTransform = headerTransform(bvc.header.frame, toFrame: finalFrame, container: container)

    bvc.footer.transform = footerForTransform
    bvc.footerBackdrop.transform = footerForTransform
    bvc.header.transform = headerForTransform
}

private func footerTransform( _ frame: CGRect, toFrame finalFrame: CGRect, container: UIView) -> CGAffineTransform {
    let frame = container.convert(frame, to: container)
    let endY = finalFrame.maxY - (frame.size.height / 2)
    let endX = finalFrame.midX
    let translation = CGPoint(x: endX - frame.midX, y: endY - frame.midY)

    let scaleX = finalFrame.width / frame.width

    var transform = CGAffineTransform.identity
    transform = transform.translatedBy(x: translation.x, y: translation.y)
    transform = transform.scaledBy(x: scaleX, y: scaleX)
    return transform
}

private func headerTransform(_ frame: CGRect, toFrame finalFrame: CGRect, container: UIView) -> CGAffineTransform {
    let frame = container.convert(frame, to: container)
    let endY = finalFrame.minY + (frame.size.height / 2)
    let endX = finalFrame.midX
    let translation = CGPoint(x: endX - frame.midX, y: endY - frame.midY)

    let scaleX = finalFrame.width / frame.width

    var transform = CGAffineTransform.identity
    transform = transform.translatedBy(x: translation.x, y: translation.y)
    transform = transform.scaledBy(x: scaleX, y: scaleX)
    return transform
}

//MARK: Private Helper Methods
private func calculateCollapsedCellFrameUsingCollectionView(_ collectionView: UICollectionView, atIndex index: Int) -> CGRect {
    if let attr = collectionView.collectionViewLayout.layoutAttributesForItem(at: IndexPath(item: index, section: 0)) {
        return collectionView.convert(attr.frame, to: collectionView.superview)
    } else {
        return CGRect.zero
    }
}

private func calculateExpandedCellFrameFromBVC(_ bvc: BrowserViewController) -> CGRect {
    var frame = bvc.webViewContainer.frame

    // If we're navigating to a home panel and we were expecting to show the toolbar, add more height to end frame since
    // there is no toolbar for home panels
    if !bvc.shouldShowFooterForTraitCollection(bvc.traitCollection) {
        return frame
    } else if AboutUtils.isAboutURL(bvc.tabManager.selectedTab?.url) && bvc.toolbar == nil {
        frame.size.height += UIConstants.ToolbarHeight
    }

    return frame
}

private func shouldDisplayFooterForBVC(_ bvc: BrowserViewController) -> Bool {
    return bvc.shouldShowFooterForTraitCollection(bvc.traitCollection) && !AboutUtils.isAboutURL(bvc.tabManager.selectedTab?.url)
}

private func toggleWebViewVisibility(_ show: Bool, usingTabManager tabManager: TabManager) {
    for i in 0..<tabManager.tabCount {
        let tab = tabManager.tabs.internalTabList[i]
        tab.webView?.isHidden = !show
    }
}

private func resetTransformsForViews(_ views: [UIView?]) {
    for view in views {
        // Reset back to origin
        view?.transform = CGAffineTransform.identity
    }
}

private func transformToolbarsToFrame(_ toolbars: [UIView?], toRect endRect: CGRect) {
    for toolbar in toolbars {
        // Reset back to origin
        toolbar?.transform = CGAffineTransform.identity

        // Transform from origin to where we want them to end up
        if let toolbarFrame = toolbar?.frame {
            toolbar?.transform = CGAffineTransformMakeRectToRect(toolbarFrame, toFrame: endRect)
        }
    }
}

private func createTransitionCellFromBrowser(_ browser: Browser?, withFrame frame: CGRect) -> TabCell {
    let cell = TabCell(frame: frame)
    cell.background.image = browser?.screenshot.image
    cell.titleLbl.text = browser?.displayTitle

    if let favIcon = browser?.displayFavicon {
        cell.favicon.sd_setImage(with: URL(string: favIcon.url)!)
    } else {
        var defaultFavicon = UIImage(named: "defaultFavicon")
        if browser?.isPrivate ?? false {
            defaultFavicon = defaultFavicon?.withRenderingMode(.alwaysTemplate)
            cell.favicon.image = defaultFavicon
            cell.favicon.tintColor = (browser?.isPrivate ?? false) ? UIColor.white : UIColor.darkGray
        } else {
            cell.favicon.image = defaultFavicon
        }
    }
    return cell
}
