/* This Source Code Form is subject to the terms of the Mozilla Public
 * License, v. 2.0. If a copy of the MPL was not distributed with this
 * file, You can obtain one at http://mozilla.org/MPL/2.0/. */

import Foundation
import SnapKit

extension UIView {
    /// Creates empty view with specified height or width parameter.
    /// Used mainly to make empty space for UIStackView
    /// Note: on iOS 11+ setCustomSpacing(value, after: View) can be used instead.
    static func spacer(_ direction: UILayoutConstraintAxis, amount: Int) -> UIView {
        let spacer = UIView()
        spacer.snp.makeConstraints { make in
            switch direction {
            case .vertical:
                make.height.equalTo(amount)
            case .horizontal:
                make.width.equalTo(amount)
            }
        }
        return spacer
    }

    /// Returns regular constraint layout DSL or uses safeAreaLayoutGuide if possible(iOS11+).
    /// This removes need of having to check for iOS availability for every constraint setup.
    var safeArea: ConstraintAttributesDSL {
        if #available(iOS 11.0, *) {
            return self.safeAreaLayoutGuide.snp
        }
        return self.snp
    }
}
