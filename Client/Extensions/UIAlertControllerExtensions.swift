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
     - parameter forcedInput: Bool whether the user needs to enter _something_ in order to enable OK button.
     - paramter callbackOnMain: Block to run on main thread when the user performs an action.
     
     - returns: UIAlertController instance
     */
    class func userTextInputAlert(title: String, message: String, startingText: String? = nil, placeholder: String? = Strings.Name, forcedInput: Bool = true, callbackOnMain: @escaping (_ input: String?) -> ()) -> UIAlertController {
        // Returning alert, so no external, strong reference to initial instance
        return UserTextInputAlert(title: title, message: message, startingText: startingText, placeholder: placeholder, forcedInput: forcedInput, callbackOnMain: callbackOnMain).alert
    }
}

// Not part of extension due to needing observing
// Would make private but objc runtime cannot find textfield observing callback
class UserTextInputAlert {
    private weak var okAction: UIAlertAction!
    private(set) var alert: UIAlertController!
    
    required init(title: String, message: String, startingText: String?, placeholder: String?, forcedInput: Bool = true, callbackOnMain: @escaping (_ input: String?) -> ()) {
        
        alert = UIAlertController(title: title, message: message, preferredStyle: .alert)
        
        func actionSelected(input: String?) {
            postAsyncToMain {
                callbackOnMain(input)
            }
            NotificationCenter.default.removeObserver(self, name: NSNotification.Name.UITextFieldTextDidChange, object: alert.textFields?.first)
        }
        
        self.okAction = UIAlertAction(title: Strings.OK, style: UIAlertActionStyle.default) { (alertA: UIAlertAction!) in
            actionSelected(input: self.alert.textFields?.first?.text)
        }
        
        let cancelAction = UIAlertAction(title: Strings.Cancel, style: UIAlertActionStyle.cancel) { (alertA: UIAlertAction!) in
            actionSelected(input: nil)
        }
        
        self.okAction.isEnabled = !forcedInput
        
        alert.addAction(self.okAction)
        alert.addAction(cancelAction)
        
        alert.addTextField {
            textField in
            textField.placeholder = placeholder
            textField.isSecureTextEntry = false
            textField.keyboardAppearance = .dark
            textField.autocapitalizationType = .words
            textField.autocorrectionType = .default
            textField.returnKeyType = .done
            textField.text = startingText
            
            if forcedInput {
                NotificationCenter.default.addObserver(self, selector: #selector(self.notificationReceived(notification:)), name: NSNotification.Name.UITextFieldTextDidChange, object: textField)
            }
        }
    }
    
    @objc func notificationReceived(notification: NSNotification) {
        if let textField = notification.object as? UITextField, let emptyText = textField.text?.isEmpty {
            okAction.isEnabled = !emptyText
        }
    }
}


