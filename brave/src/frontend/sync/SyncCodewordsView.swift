/* This Source Code Form is subject to the terms of the Mozilla Public License, v. 2.0. If a copy of the MPL was not distributed with this file, You can obtain one at http://mozilla.org/MPL/2.0/. */

class SyncCodewordsView: UIView, UITextFieldDelegate {
    var fields: [UITextField] = []
    
    let DefaultBackgroundColor = UIColor(rgb: 0xcccccc)
    let SelectedBackgroundColor = UIColor.white
    
    let DefaultBorderWidth: CGFloat = 0.0
    let SelectedBorderWidth: CGFloat = 0.5
    
    let DefaultBorderColor = UIColor(rgb: 0x696969).cgColor
    
    var doneKeyCallback: (() -> Void)?
    
    convenience init(data: [String]) {
        self.init()
        
        for i in 0...15 {
            let field = UITextField()
            field.delegate = self
            field.tag = i
            field.font = UIFont.systemFont(ofSize: 14, weight: UIFontWeightRegular)
            field.textAlignment = .center
            field.textColor = UIColor.black
            field.keyboardAppearance = .dark
            field.autocapitalizationType = .none
            field.autocorrectionType = .no
            field.returnKeyType = i < 15 ? .continue : .done
            field.text = data.count > i ? data[i] : ""
            field.backgroundColor = DefaultBackgroundColor
            field.layer.cornerRadius = 4
            field.layer.masksToBounds = true
            field.layer.borderWidth = DefaultBorderWidth
            field.layer.borderColor = DefaultBorderColor
            field.placeholder = "\(i + 1)"
            addSubview(field)
            fields.append(field)
        }
        
        // Read-only if data passed.
        if !data.isEmpty {
            fields.forEach { $0.isEnabled = false }
        }
    }
    
    func codeWords() -> [String] {
        return [""]
        // TODO: Need `.withoutSpaces`
//        return fields.map { $0.text?.withoutSpaces }.filter { $0?.characters.count > 0 }.flatMap { $0 }
    }
    
    override func layoutSubviews() {
        let spaceX: CGFloat = 18
        let spaceY: CGFloat = 7
        var x: CGFloat = 0
        var y: CGFloat = 0
        let w: CGFloat = (UIScreen.main.bounds.width - spaceX * 4) / 3
        let h: CGFloat = 26
        for i in 0..<fields.count {
            x = x + spaceX
            if x + w > UIScreen.main.bounds.width {
                x = spaceX
                y = y + h + spaceY
            }
            if i == fields.count - 1 {
                // Center last.
                x = (UIScreen.main.bounds.width - w) / 2
            }
            // debugPrint("w \(w) x \(x) y\(y)")
            
            let field = fields[i]
            var fieldFrame = field.frame
            fieldFrame.origin.x = x
            fieldFrame.origin.y = y
            fieldFrame.size.width = w
            fieldFrame.size.height = h
            field.frame = fieldFrame
            
            x = x + w
        }
    }
    
    override func sizeToFit() {
        let field = fields[fields.count - 1]
        var f = frame
        f.size.width = UIScreen.main.bounds.width
        f.size.height = field.frame.maxY
        frame = f
    }
    
    func textFieldDidBeginEditing(_ textField: UITextField) {
        textField.layer.borderWidth = SelectedBorderWidth
        textField.backgroundColor = SelectedBackgroundColor
        
        // Clear text, much easier to retype then attempt to edit inline
        textField.text = nil
    }
    
    func textFieldDidEndEditing(_ textField: UITextField) {
        textField.layer.borderWidth = DefaultBorderWidth
        textField.backgroundColor = DefaultBackgroundColor
    }
    
    func textFieldShouldReturn(_ textField: UITextField) -> Bool {
        if textField.tag < fields.count - 1 {
            let field = fields[textField.tag + 1]
            field.becomeFirstResponder()
        } else {
            doneKeyCallback?()
        }
        return true
    }
    
    func textField(_ textField: UITextField, shouldChangeCharactersIn range: NSRange, replacementString string: String) -> Bool {
        
        guard let text = textField.text else {
            return true
        }
        
        // Filter out whitespace and apply change to current text
        // TODO: Need to add `.withoutWhitespace`
//        let result = text.replacingCharacters(in: range, with: string)
        let result = ""
        
        // Manually apple text to have better control over what is being entered
        //  Could use this for custom autocomplete for pre-defined keywords
        textField.text = result
        
        return false
    }
}
