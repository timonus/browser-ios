/* This Source Code Form is subject to the terms of the Mozilla Public License, v. 2.0. If a copy of the MPL was not distributed with this file, You can obtain one at http://mozilla.org/MPL/2.0/. */

import UIKit
import Shared
import SnapKit

class SyncDeviceTypeButton: UIControl {
    
    var imageView: UIImageView = UIImageView()
    var label: UILabel = UILabel()
    
    convenience init(image: UIImage, title: String) {
        self.init(frame: CGRect.zero)
        
        imageView.image = image
        imageView.contentMode = .center
        imageView.tintColor = UIColor.black
        addSubview(imageView)
        
        label.text = title
        label.font = UIFont.systemFont(ofSize: 17.0, weight: UIFontWeightBold)
        label.textColor = UIColor.black
        addSubview(label)
        
        imageView.snp.makeConstraints { (make) in
            make.center.equalTo(superview!.center)
        }
        
        imageView.snp.makeConstraints { (make) in
            make.top.equalTo(imageView.snp.bottom).offset(20)
            make.centerX.equalTo(superview!.center)
            make.leftMargin.rightMargin.equalTo(40)
        }
    }
    
    override init(frame: CGRect) {
        super.init(frame: frame)
    }
    
    required init?(coder aDecoder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    
}

class SyncAddDeviceTypeViewController: UIViewController {
    
    var scrollView: UIScrollView!
    var phoneTabletButton: UIButton!
    var computerButton: UIButton!
    
    override func viewDidLoad() {
        super.viewDidLoad()
        
        title = Strings.Sync
        view.backgroundColor = SyncBackgroundColor
        
        scrollView = UIScrollView()
        scrollView.translatesAutoresizingMaskIntoConstraints = false
        scrollView.alwaysBounceVertical = true
        view.addSubview(scrollView)
        
        edgesForExtendedLayout = UIRectEdge()
        
        scrollView.snp.makeConstraints { (make) in
            make.edges.equalTo(self.view)
        }
    }
}

