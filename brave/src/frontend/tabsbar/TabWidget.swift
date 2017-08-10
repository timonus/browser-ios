/* This Source Code Form is subject to the terms of the Mozilla Public License, v. 2.0. If a copy of the MPL was not distributed with this file, You can obtain one at http://mozilla.org/MPL/2.0/. */
import UIKit
import SnapKit

protocol TabWidgetDelegate: class {
    func tabWidgetClose(_ tab: TabWidget)
    func tabWidgetSelected(_ tab: TabWidget)
    func tabWidgetDragMoved(_ tab: TabWidget, distance: CGFloat, isEnding: Bool)
    func tabWidgetDragStarted(_ tab: TabWidget)
}

let labelInsetFromRight = CGFloat(24)

class TabDragClone : UIImageView {
    let parent: TabWidget
    required init(parent: TabWidget, frame: CGRect) {
        self.parent = parent
        super.init(frame: frame)
        layer.borderWidth = 1
        layer.borderColor = UIColor.black.withAlphaComponent(0.4).cgColor
        backgroundColor = UIColor.black.withAlphaComponent(0.2)
    }

    required init?(coder aDecoder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    var lastLocation:CGPoint?
    var translation:CGPoint!
    func detectPan(_ recognizer:UIPanGestureRecognizer) {
        if lastLocation == nil {
            lastLocation = self.center
        }
        translation = recognizer.translation(in: superview!)
        center = CGPoint(x: lastLocation!.x + translation.x, y: lastLocation!.y)
    }

    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent?) {
        self.superview?.bringSubview(toFront: self)
        lastLocation = self.center
    }

    override func touchesEnded(_ touches: Set<UITouch>, with event: UIEvent?) {
        if let lastLocation = lastLocation {
            center = lastLocation
        }
        lastLocation = nil
        alpha = 1.0
    }
}

class TabWidget : UIView {
    let title = UIButton()
    let close = UIButton()
    weak var delegate: TabWidgetDelegate?
    fileprivate(set) weak var browser: Browser?
    var widthConstraint: Constraint? = nil

    // Drag and drop items
    var dragClone: TabDragClone?
    let spacerRight = UIView()
    var pan: UIPanGestureRecognizer!
    let separatorLine = UIView() // visibility is controlled by TabsBarViewController

    init(browser: Browser, parentScrollView: UIScrollView) {
        super.init(frame: CGRect.zero)
        parentScrollView.addSubview(spacerRight)

        self.translatesAutoresizingMaskIntoConstraints = false
        self.browser = browser

        if let wv = browser.webView {
            wv.delegatesForPageState.append(BraveWebView.Weak_WebPageStateDelegate(value: self))
        }


        close.addTarget(self, action: #selector(clicked), for: .touchUpInside)
        title.addTarget(self, action: #selector(selected), for: .touchUpInside)
        title.setTitle("", for: .normal)
        [close, title, separatorLine].forEach { addSubview($0) }

        close.setImage(UIImage(named: "stop")?.withRenderingMode(.alwaysTemplate), for: .normal)
        close.snp.makeConstraints({ (make) in
            make.top.bottom.equalTo(self)
            make.left.equalTo(self).inset(4)
            make.width.equalTo(24)
        })
        close.tintColor = UIColor.black

        reinstallConstraints()

        separatorLine.backgroundColor = UIColor.black.withAlphaComponent(0.2)
        separatorLine.snp.makeConstraints { (make) in
            make.left.equalTo(self)
            make.width.equalTo(1)
            make.height.equalTo(22)
            make.centerY.equalTo(self.snp.centerY)
        }

        deselect()

        clipsToBounds = true
        translatesAutoresizingMaskIntoConstraints = false
        let g = UILongPressGestureRecognizer(target: self, action: #selector(longPress))
        g.delegate = self
        title.addGestureRecognizer(g)

        pan = UIPanGestureRecognizer(target:self, action:#selector(detectPan(_:)))
        parentScrollView.addGestureRecognizer(pan)
        pan.delegate = self

    }

    func reinstallConstraints() {
        title.snp.remakeConstraints { (make) in
            make.top.bottom.equalTo(self)
            make.left.equalTo(close.snp.right)
            make.right.equalTo(self).inset(labelInsetFromRight)
        }
    }

    func breakConstraintsForShrinking() {
        title.snp.remakeConstraints { (make) in
            make.top.bottom.equalTo(self)
            make.left.lessThanOrEqualTo(close.snp.right)
            make.width.lessThanOrEqualTo(title.frame.width)
            make.right.greaterThanOrEqualTo(self).inset(labelInsetFromRight)
        }
    }

    required init?(coder aDecoder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func clicked() {
        delegate?.tabWidgetClose(self)
    }

    func deselect() {
        backgroundColor = UIColor.init(white: 0.0, alpha: 0.1)
        title.titleLabel!.font = UIFont.systemFont(ofSize: 12)
        title.setTitleColor(PrivateBrowsing.singleton.isOn ? UIColor(white: 1.0, alpha: 0.4) : UIColor(white: 0.0, alpha: 0.4), for: .normal)
        close.isHidden = true
        close.tintColor = PrivateBrowsing.singleton.isOn ? UIColor.white : UIColor.black
    }

    func selected() {
        delegate?.tabWidgetSelected(self)
    }

    func setStyleToSelected() {
        title.titleLabel!.font = UIFont.systemFont(ofSize: 12, weight: UIFontWeightSemibold)
        title.setTitleColor(PrivateBrowsing.singleton.isOn ? UIColor.white : UIColor.black, for: .normal)
        backgroundColor = UIColor.clear
        close.isHidden = false
        
    }

    func isSelectedStyle() -> Bool {
        return !close.isHidden
    }

    fileprivate var titleUpdateScheduled = false
    func updateTitle_throttled() {
        if titleUpdateScheduled {
            return
        }
        titleUpdateScheduled = true
        postAsyncToMain(0.2) { [weak self] in
            self?.titleUpdateScheduled = false
            if let t = self?.browser?.webView?.title, !t.isEmpty {
                self?.setTitle(t)
            }
        }
    }

    func setTitle(_ title: String?) {
        if let title = title, title != "localhost" {
            self.title.setTitle(title, for: .normal)
        } else {
            self.title.setTitle("", for: .normal)
        }
    }
}

extension TabWidget : WebPageStateDelegate {
    func webView(_ webView: UIWebView, urlChanged: String) {
        if let t = browser?.url?.baseDomain,  title.titleLabel?.text?.isEmpty ?? true {
            setTitle(t)
        }

        updateTitle_throttled()
    }

    func webView(_ webView: UIWebView, progressChanged: Float) {
        updateTitle_throttled()
    }

    func webView(_ webView: UIWebView, isLoading: Bool) {}
    func webView(_ webView: UIWebView, canGoBack: Bool) {}
    func webView(_ webView: UIWebView, canGoForward: Bool) {}
}

extension TabWidget : UIGestureRecognizerDelegate {
    func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer, shouldRecognizeSimultaneouslyWith otherGestureRecognizer: UIGestureRecognizer) -> Bool {
        return true
    }
}

extension TabWidget {
    func remakeLayout(_ prev: UIView, width: CGFloat, scrollView: UIView) {
        snp.remakeConstraints {
            make in
            widthConstraint = make.width.equalTo(width).constraint
            make.height.equalTo(tabHeight)
            make.left.equalTo(prev.snp.right)
            make.top.equalTo(0)
        }

        spacerRight.snp.remakeConstraints
            { (make) in
                make.top.equalTo(scrollView)
                make.height.equalTo(tabHeight)
                make.left.equalTo(snp.right)
                make.width.equalTo(0)
                make.top.equalTo(0)
        }
    }

    func longPress(_ g: UILongPressGestureRecognizer) {
        if g.state == .ended {
            postAsyncToMain(0.1) {
                if let dragClone = self.dragClone, dragClone.lastLocation == nil {
                    dragClone.removeFromSuperview()
                    self.dragClone = nil
                    self.alpha = 1.0
                }
            }
        }

        if dragClone != nil || g.state != .began {
            return
        }

        delegate?.tabWidgetDragStarted(self)

        dragClone = TabDragClone(parent: self, frame: frame)
        UIGraphicsBeginImageContextWithOptions(bounds.size, false, 0.0)
        guard let context = UIGraphicsGetCurrentContext() else { return }
        layer.render(in: context)
        let screenShot = UIGraphicsGetImageFromCurrentImageContext()
        UIGraphicsEndImageContext()
        dragClone!.image = screenShot
        superview!.addSubview(dragClone!)
        alpha = 0
    }

    func detectPan(_ recognizer:UIPanGestureRecognizer) {
        if let dragClone = dragClone {
            dragClone.detectPan(recognizer)
            delegate?.tabWidgetDragMoved(self, distance: recognizer.translation(in: superview!).x, isEnding: recognizer.state == .ended)
        }
    }
}

