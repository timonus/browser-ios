/* This Source Code Form is subject to the terms of the Mozilla Public License, v. 2.0. If a copy of the MPL was not distributed with this file, You can obtain one at http://mozilla.org/MPL/2.0/. */

import Shared

class SyncCodewordsView: UIView, UITextViewDelegate {
    lazy var field: UITextView = {
        let textView = UITextView()
        textView.autocapitalizationType = .none
        textView.autocorrectionType = .yes
        textView.font = UIFont.systemFont(ofSize: 18, weight: UIFontWeightMedium)
        textView.textColor = BraveUX.GreyJ
        return textView
    }()
    
    lazy var placeholder: UILabel = {
        let label = UILabel()
        label.text = Strings.CodeWordInputHelp
        label.font = UIFont.systemFont(ofSize: 18, weight: UIFontWeightRegular)
        label.textColor = BraveUX.GreyE
        label.lineBreakMode = .byWordWrapping
        label.numberOfLines = 0
        return label
    }()
    
    var wordCountChangeCallback: ((_ count: Int) -> Void)?
    var currentWordCount = 0
    
    convenience init(data: [String]) {
        self.init()
        
        translatesAutoresizingMaskIntoConstraints = false
        
        addSubview(field)
        addSubview(placeholder)
        
        setCodewords(data: data)
        
        field.snp.makeConstraints { (make) in
            make.edges.equalTo(self).inset(20)
        }

        placeholder.snp.makeConstraints { (make) in
            make.top.left.right.equalTo(field).inset(UIEdgeInsetsMake(8, 4, 0, 0))
        }
        
        field.delegate = self
    }
    
    func setCodewords(data: [String]) {
        field.text = data.count > 0 ? data.joined(separator: " ") : ""
        
        updateWordCount()
    }
    
    func codeWords() -> [String] {
        let text = field.text.trimmingCharacters(in: .whitespacesAndNewlines)
        return text.components(separatedBy: " ").filter { $0.count > 0 }
    }
    
    func wordCount() -> Int {
        let words = codeWords()
        var count = words.count
        // Don't count if it's just a space (no characters entered for new word)
        if count > 0, let last = words.last, last.count < 1 {
            count -= 1
        }
        return count
    }
    
    func updateWordCount() {
        placeholder.isHidden = (field.text.count != 0)
        
        let wordCount = self.wordCount()
        if wordCount != currentWordCount {
            currentWordCount = wordCount
            wordCountChangeCallback?(wordCount)
        }
    }
    
    @discardableResult override func becomeFirstResponder() -> Bool {
        field.becomeFirstResponder()
        return true
    }
    
    func textView(_ textView: UITextView, shouldChangeTextIn range: NSRange, replacementText text: String) -> Bool {
        return text != "\n"
    }
    
    func textViewDidChange(_ textView: UITextView) {
        updateWordCount()
    }
}
