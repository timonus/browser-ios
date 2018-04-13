/* This Source Code Form is subject to the terms of the Mozilla Public
 * License, v. 2.0. If a copy of the MPL was not distributed with this
 * file, You can obtain one at http://mozilla.org/MPL/2.0/. */

import UIKit
import Shared

typealias UIAlertActionCallback = (UIAlertAction) -> Void

// TODO: Build out this functionality a bit more (and remove FF code).
//  We have a number of "cancel" "yes" type alerts, should abstract here

// MARK: - Extension methods for building specific UIAlertController instances used across the app
extension UIAlertController {

    class func clearPrivateDataAlert(_ okayCallback: @escaping (UIAlertAction) -> Void) -> UIAlertController {
        let alert = UIAlertController(
            title: "",
            message: Strings.ThisWillClearAllPrivateDataItCannotBeUndone,
            preferredStyle: UIAlertControllerStyle.alert
        )

        let noOption = UIAlertAction(
            title: Strings.Cancel,
            style: UIAlertActionStyle.cancel,
            handler: nil
        )

        let okayOption = UIAlertAction(
            title: Strings.OK,
            style: UIAlertActionStyle.destructive,
            handler: okayCallback
        )

        alert.addAction(okayOption)
        alert.addAction(noOption)
        return alert
    }

    /**
     Creates an alert view to warn the user that their logins will either be completely deleted in the 
     case of local-only logins or deleted across synced devices in synced account logins.

     - parameter deleteCallback: Block to run when delete is tapped.
     - parameter hasSyncedLogins: Boolean indicating the user has logins that have been synced.

     - returns: UIAlertController instance
     */
    class func deleteLoginAlertWithDeleteCallback(
        _ deleteCallback: @escaping UIAlertActionCallback,
        hasSyncedLogins: Bool) -> UIAlertController {

        let areYouSureTitle = Strings.AreYouSure
        let deleteLocalMessage = Strings.LoginsWillBePermanentlyRemoved
        let deleteSyncedDevicesMessage = Strings.LoginsWillBeRemovedFromAllConnectedDevices
        let cancelActionTitle = Strings.Cancel
        let deleteActionTitle = Strings.Delete

        let deleteAlert: UIAlertController
        if hasSyncedLogins {
            deleteAlert = UIAlertController(title: areYouSureTitle, message: deleteSyncedDevicesMessage, preferredStyle: .alert)
        } else {
            deleteAlert = UIAlertController(title: areYouSureTitle, message: deleteLocalMessage, preferredStyle: .alert)
        }

        let cancelAction = UIAlertAction(title: cancelActionTitle, style: .cancel, handler: nil)
        let deleteAction = UIAlertAction(title: deleteActionTitle, style: .destructive, handler: deleteCallback)

        deleteAlert.addAction(cancelAction)
        deleteAlert.addAction(deleteAction)

        return deleteAlert
    }
    
    
    // Enabled this facade for much easier discoverability, instead of using class directly
    /**
     Creates an alert view to collect a string from the user
     
     - parameter title: String to display as the alert title.
     - parameter message: String to display as the alert message.
     - parameter startingText: String to prefill the textfield with.
     - parameter placeholder: String to use for the placeholder text on the text field.
     - parameter keyboardType: Keyboard type of the text field.
     - parameter startingText2: String to prefill the second optional textfield with.
     - parameter placeholder2: String to use for the placeholder text on the second optional text field.
     - parameter keyboardType2: Keyboard type of the text second optional field.
     - parameter forcedInput: Bool whether the user needs to enter _something_ in order to enable OK button.
     - parameter callbackOnMain: Block to run on main thread when the user performs an action.
     
     - returns: UIAlertController instance
     */
    class func userTextInputAlert(title: String,
                                  message: String,
                                  startingText: String? = nil,
                                  placeholder: String? = Strings.Name,
                                  keyboardType: UIKeyboardType? = nil,
                                  startingText2: String? = nil,
                                  placeholder2: String? = Strings.Name,
                                  keyboardType2: UIKeyboardType? = nil,
                                  forcedInput: Bool = true,
                                  callbackOnMain: @escaping (_ input: String?, _ input2: String?) -> ()) -> UIAlertController {
        // Returning alert, so no external, strong reference to initial instance
        return UserTextInputAlert(title: title, message: message, startingText: startingText, placeholder: placeholder,
                                  startingText2: startingText2, placeholder2: placeholder2, forcedInput: forcedInput,
                                  callbackOnMain: callbackOnMain).alert
    }

}

// Not part of extension due to needing observing
// Would make private but objc runtime cannot find textfield observing callback
class UserTextInputAlert {
    private weak var okAction: UIAlertAction!
    private(set) var alert: UIAlertController!
    
    required init(title: String, message: String,
                  startingText: String?,
                  placeholder: String?,
                  keyboardType: UIKeyboardType? = nil,
                  startingText2: String? = nil,
                  placeholder2: String? = nil,
                  keyboardType2: UIKeyboardType? = nil,
                  forcedInput: Bool = true,
                  callbackOnMain: @escaping (_ input: String?, _ input2: String?) -> ()) {
        
        alert = UIAlertController(title: title, message: message, preferredStyle: .alert)
        
        func actionSelected(input: String?, input2: String?) {
            postAsyncToMain {
                callbackOnMain(input, input2)
            }
            NotificationCenter.default.removeObserver(self, name: NSNotification.Name.UITextFieldTextDidChange, object: alert.textFields?.first)
        }
        
        let okAction = UIAlertAction(title: Strings.OK, style: UIAlertActionStyle.default) { (alertA: UIAlertAction!) in
            actionSelected(input: self.alert.textFields?.first?.text, input2: self.alert.textFields?.last?.text)
        }
        
        let cancelAction = UIAlertAction(title: Strings.Cancel, style: UIAlertActionStyle.cancel) { (alertA: UIAlertAction!) in
            actionSelected(input: nil, input2: nil)
        }
        
        okAction.isEnabled = !forcedInput
        
        alert.addAction(okAction)
        alert.addAction(cancelAction)
        
        self.okAction = okAction
        
        alert.addTextField {
            textField in
            textField.placeholder = placeholder
            textField.isSecureTextEntry = false
            textField.keyboardAppearance = .dark
            textField.autocapitalizationType = .words
            textField.autocorrectionType = .default
            textField.returnKeyType = .done
            textField.text = startingText
            textField.keyboardType = keyboardType ?? .default
            
            if forcedInput {
                NotificationCenter.default.addObserver(self, selector: #selector(self.notificationReceived(notification:)), name: NSNotification.Name.UITextFieldTextDidChange, object: textField)
            }
        }

        // TODO: Abstract to an array of textfields to DRY?
        if let text2 = startingText2 {
            alert.addTextField {
                textField in
                textField.placeholder = placeholder2
                textField.isSecureTextEntry = false
                textField.keyboardAppearance = .dark
                textField.autocapitalizationType = .words
                textField.autocorrectionType = .default
                textField.returnKeyType = .done
                textField.text = text2
                textField.keyboardType = keyboardType2 ?? .default

                if forcedInput {
                    NotificationCenter.default.addObserver(self, selector: #selector(self.notificationReceived(notification:)), name: NSNotification.Name.UITextFieldTextDidChange, object: textField)
                }
            }
        }
    }
    
    @objc func notificationReceived(notification: NSNotification) {
        guard let textFields = alert.textFields, let firstText = textFields.first?.text  else { return }

        switch textFields.count {
        case 1:
            okAction.isEnabled = !firstText.isEmpty
        case 2:
            guard let lastText = textFields.last?.text else { break }
            okAction.isEnabled = !firstText.isEmpty && !lastText.isEmpty
        default:
            return
        }
    }
}


