/* This Source Code Form is subject to the terms of the Mozilla Public
 * License, v. 2.0. If a copy of the MPL was not distributed with this
 * file, You can obtain one at http://mozilla.org/MPL/2.0/. */

import Foundation
import UIKit
import SnapKit
import Shared
import XCGLogger

private let log = Logger.browserLogger

enum ReaderModeBarButtonType {
    case markAsRead, markAsUnread, settings, addToReadingList, removeFromReadingList

    fileprivate var localizedDescription: String {
        switch self {
        case .markAsRead: return Strings.Mark_as_Read
        case .markAsUnread: return Strings.Mark_as_Unread
        case .settings: return Strings.Reader_Mode_Settings
        case .addToReadingList: return Strings.Add_to_Reading_List
        case .removeFromReadingList: return Strings.Remove_from_Reading_List
        }
    }

    fileprivate var imageName: String {
        switch self {
        case .markAsRead: return "MarkAsRead"
        case .markAsUnread: return "MarkAsUnread"
        case .settings: return "SettingsSerif"
        case .addToReadingList: return "addToReadingList"
        case .removeFromReadingList: return "removeFromReadingList"
        }
    }

    fileprivate var image: UIImage? {
        let image = UIImage(named: imageName)
        image?.accessibilityLabel = localizedDescription
        return image
    }
}

protocol ReaderModeBarViewDelegate {
    func readerModeBar(_ readerModeBar: ReaderModeBarView, didSelectButton buttonType: ReaderModeBarButtonType)
}

struct ReaderModeBarViewUX {

    static let Themes: [String: Theme] = {
        var themes = [String: Theme]()
        var theme = Theme()
        theme.backgroundColor = UIConstants.PrivateModeReaderModeBackgroundColor
        theme.buttonTintColor = UIColor.white
        themes[Theme.PrivateMode] = theme

        theme = Theme()
        theme.backgroundColor = UIColor.white
        theme.buttonTintColor = UIColor.darkGray
        themes[Theme.NormalMode] = theme

        return themes
    }()
}

class ReaderModeBarView: UIView {
    var delegate: ReaderModeBarViewDelegate?
    var settingsButton: UIButton!

    dynamic var buttonTintColor: UIColor = UIColor.clear {
        didSet {
            settingsButton.tintColor = self.buttonTintColor
        }
    }

    override init(frame: CGRect) {
        super.init(frame: frame)

        // This class is glued on to the bottom of the urlbar, and is outside of that frame, so we have to manually
        // route clicks here. See see BrowserViewController.ViewToCaptureReaderModeTap
        // TODO: Redo urlbar layout so that we can place this within the frame *if* we decide to keep the reader settings attached to urlbar
        settingsButton = UIButton()
        settingsButton.setTitleColor(BraveUX.BraveOrange, for: .normal)
        settingsButton.titleLabel?.font = UIFont.boldSystemFont(ofSize: UIFont.systemFontSize - 1)
        settingsButton.setTitle(Strings.Reader_Mode_Settings, for: .normal)
        settingsButton.addTarget(self, action: #selector(ReaderModeBarView.SELtappedSettingsButton), for: .touchUpInside)
        settingsButton.accessibilityLabel = Strings.Reader_Mode_Settings
        addSubview(settingsButton)

        settingsButton.snp.makeConstraints { make in
            make.centerX.centerY.equalTo(self)

        }
        self.backgroundColor = UIColor.white.withAlphaComponent(1.0)
    }

    required init?(coder aDecoder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func draw(_ rect: CGRect) {
        super.draw(rect)
        let context = UIGraphicsGetCurrentContext()
        context!.setLineWidth(0.5)
        context!.setStrokeColor(red: 0.1, green: 0.1, blue: 0.1, alpha: 1.0)
        context!.setStrokeColor(UIColor.gray.cgColor)
        context!.beginPath()
        context!.move(to: CGPoint(x: 0, y: frame.height))
        context!.addLine(to: CGPoint(x: frame.width, y: frame.height))
        context!.strokePath()
    }

    func SELtappedSettingsButton() {
        delegate?.readerModeBar(self, didSelectButton: .settings)
    }

}

//extension ReaderModeBarView: Themeable {
//    func applyTheme(themeName: String) {
//        guard let theme = ReaderModeBarViewUX.Themes[themeName] else {
//            log.error("Unable to apply unknown theme \(themeName)")
//            return
//        }
//
//        backgroundColor = theme.backgroundColor
//        buttonTintColor = theme.buttonTintColor!
//    }
//}
