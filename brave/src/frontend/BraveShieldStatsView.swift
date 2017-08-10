/* This Source Code Form is subject to the terms of the Mozilla Public
 * License, v. 2.0. If a copy of the MPL was not distributed with this
 * file, You can obtain one at http://mozilla.org/MPL/2.0/. */

import Foundation
import Shared

class BraveShieldStatsView: UIView {
    fileprivate let millisecondsPerItem = 50
    fileprivate let line = UIView()
    
    lazy var adsStatView: StatView = {
        let statView = StatView(frame: CGRect.zero)
        statView.title = Strings.ShieldsAdStats
        statView.color = UIColor(red: 254/255.0, green: 82/255.0, blue: 29/255.0, alpha: 1.0)
        return statView
    }()

    lazy var trackersStatView: StatView = {
        let statView = StatView(frame: CGRect.zero)
        statView.title = Strings.ShieldsTrackerStats
        statView.color = UIColor(red: 243/255.0, green: 144/255.0, blue: 48/255.0, alpha: 1.0)
        return statView
    }()

    lazy var httpsStatView: StatView = {
        let statView = StatView(frame: CGRect.zero)
        statView.title = Strings.ShieldsHttpsStats
        statView.color = UIColor(red: 7/255.0, green: 150/255.0, blue: 250/255.0, alpha: 1.0)
        return statView
    }()

    lazy var timeStatView: StatView = {
        let statView = StatView(frame: CGRect.zero)
        statView.title = Strings.ShieldsTimeStats
        // Color dynamically set in controller: TopSitesPanel, should be abstracted
        statView.color = PrivateBrowsing.singleton.isOn ? .white : .black
        return statView
    }()
    
    lazy var stats: [StatView] = {
        return [self.trackersStatView, self.adsStatView, self.httpsStatView, self.timeStatView]
    }()
    
    override init(frame: CGRect) {
        super.init(frame: frame)
        
        addSubview(line)
        line.backgroundColor = UIColor(white: 0.0, alpha: 0.2)
        line.snp.makeConstraints { (make) -> Void in
            make.bottom.equalTo(0).offset(-0.5)
            make.height.equalTo(0.5)
            make.left.equalTo(0)
            make.right.equalTo(0)
        }
        
        for s: StatView in stats {
            addSubview(s)
        }
        
        update()
        
        NotificationCenter.default.addObserver(self, selector: #selector(update), name: NSNotification.Name(rawValue: BraveGlobalShieldStats.DidUpdateNotification), object: nil)
    }
    
    required init?(coder aDecoder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    deinit {
        NotificationCenter.default.removeObserver(self)
    }
    
    override func layoutSubviews() {
        let width: CGFloat = frame.width / CGFloat(stats.count)
        var offset: CGFloat = 0
        for s: StatView in stats {
            var f: CGRect = s.frame
            f.origin.x = offset
            f.size = CGSize(width: width, height: frame.height)
            s.frame = f
            offset += width
        }
    }
    
    func update() {
        adsStatView.stat = BraveGlobalShieldStats.singleton.adblock.abbreviation
        trackersStatView.stat = BraveGlobalShieldStats.singleton.trackingProtection.abbreviation
        httpsStatView.stat = BraveGlobalShieldStats.singleton.httpse.abbreviation
        timeStatView.stat = timeSaved
    }
    
    var timeSaved: String {
        get {
            let estimatedMillisecondsSaved = (BraveGlobalShieldStats.singleton.adblock + BraveGlobalShieldStats.singleton.trackingProtection) * millisecondsPerItem
            let hours = estimatedMillisecondsSaved < 1000 * 60 * 60 * 24
            let minutes = estimatedMillisecondsSaved < 1000 * 60 * 60
            let seconds = estimatedMillisecondsSaved < 1000 * 60
            var counter: Double = 0
            var text = ""
            
            if seconds {
                counter = ceil(Double(estimatedMillisecondsSaved / 1000))
                text = Strings.ShieldsTimeStatsSeconds
            }
            else if minutes {
                counter = ceil(Double(estimatedMillisecondsSaved / 1000 / 60))
                text = Strings.ShieldsTimeStatsMinutes
            }
            else if hours {
                counter = ceil(Double(estimatedMillisecondsSaved / 1000 / 60 / 60))
                text = Strings.ShieldsTimeStatsHour
            }
            else {
                counter = ceil(Double(estimatedMillisecondsSaved / 1000 / 60 / 60 / 24))
                text = Strings.ShieldsTimeStatsDays
            }
            
            return "\(Int(counter))\(text)"
        }
    }
}

class StatView: UIView {
    var color: UIColor = UIColor.black {
        didSet {
            statLabel.textColor = color
        }
    }
    
    var stat: String = "" {
        didSet {
            statLabel.text = "\(stat)"
        }
    }
    
    var title: String = "" {
        didSet {
            titleLabel.text = "\(title)"
        }
    }
    
    fileprivate var statLabel: UILabel = {
        let label = UILabel()
        label.textAlignment = .center
        label.numberOfLines = 0
        label.font = UIFont.systemFont(ofSize: 24, weight: UIFontWeightBold)
        return label
    }()
    
    fileprivate var titleLabel: UILabel = {
        let label = UILabel()
        label.textColor = BraveUX.TopSitesStatTitleColor
        label.textAlignment = .center
        label.numberOfLines = 0
        label.font = UIFont.systemFont(ofSize: 12, weight: UIFontWeightMedium)
        return label
    }()
    
    override init(frame: CGRect) {
        super.init(frame: frame)
        
        addSubview(statLabel)
        addSubview(titleLabel)
        
        statLabel.snp.makeConstraints({ (make) -> Void in
            make.left.equalTo(0)
            make.right.equalTo(0)
            make.centerY.equalTo(self).offset(-(statLabel.sizeThatFits(CGSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)).height)-10)
        })
        
        titleLabel.snp.makeConstraints({ (make) -> Void in
            make.left.equalTo(0)
            make.right.equalTo(0)
            make.top.equalTo(statLabel.snp.bottom).offset(5)
        })
    }
    
    required init?(coder aDecoder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
}
