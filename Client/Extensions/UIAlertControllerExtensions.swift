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

    class func clearPrivateDataAlert(okayCallback: (UIAlertAction) -> Void) -> UIAlertController {
        let alert = UIAlertController(
            title: "",
            message: Strings.ThisWillClearAllPrivateDataItCannotBeUndone,
            preferredStyle: UIAlertControllerStyle.Alert
        )

        let noOption = UIAlertAction(
            title: Strings.Cancel,
            style: UIAlertActionStyle.Cancel,
            handler: nil
        )

        let okayOption = UIAlertAction(
            title: Strings.OK,
            style: UIAlertActionStyle.Destructive,
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
        deleteCallback: UIAlertActionCallback,
        hasSyncedLogins: Bool) -> UIAlertController {

        let areYouSureTitle = Strings.AreYouSure
        let deleteLocalMessage = Strings.LoginsWillBePermanentlyRemoved
        let deleteSyncedDevicesMessage = Strings.LoginsWillBeRemovedFromAllConnectedDevices
        let cancelActionTitle = Strings.Cancel
        let deleteActionTitle = Strings.Delete

        let deleteAlert: UIAlertController
        if hasSyncedLogins {
            deleteAlert = UIAlertController(title: areYouSureTitle, message: deleteSyncedDevicesMessage, preferredStyle: .Alert)
        } else {
            deleteAlert = UIAlertController(title: areYouSureTitle, message: deleteLocalMessage, preferredStyle: .Alert)
        }

        let cancelAction = UIAlertAction(title: cancelActionTitle, style: .Cancel, handler: nil)
        let deleteAction = UIAlertAction(title: deleteActionTitle, style: .Destructive, handler: deleteCallback)

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
    class func userTextInputAlert(title title: String, message: String, startingText: String? = nil, placeholder: String? = "Name", forcedInput: Bool = true, callbackOnMain: (input: String?) -> ()) -> UIAlertController {
        return UserTextInputAlert(title: title, message: message, startingText: startingText, placeholder: placeholder, forcedInput: forcedInput, callbackOnMain: callbackOnMain)
    }
}

// Not part of extension due to needing observing
// Would make private but objc runtime cannot find textfield observing callback
class UserTextInputAlert: UIAlertController {
    private weak var okAction: UIAlertAction!

    init(title: String, message: String, startingText: String?, placeholder: String?, forcedInput: Bool = true, callbackOnMain: (input: String?) -> ()) {
        super.init(nibName: nil, bundle: nil)
        self.title = title
        self.message = message
        
        func actionSelected(input input: String?) {
            postAsyncToMain {
                callbackOnMain(input: input)
            }
            NSNotificationCenter.defaultCenter().removeObserver(self, name: UITextFieldTextDidChangeNotification, object: self.textFields?.first)
        }
        
        okAction = UIAlertAction(title: "OK", style: UIAlertActionStyle.Default) { (alertA: UIAlertAction!) in
            actionSelected(input: self.textFields?.first?.text)
        }
        
        let cancelAction = UIAlertAction(title: "Cancel", style: UIAlertActionStyle.Cancel) { (alertA: UIAlertAction!) in
            actionSelected(input: nil)
        }
        
        okAction.enabled = !forcedInput
        
        self.addAction(okAction)
        self.addAction(cancelAction)
        
        self.addTextFieldWithConfigurationHandler {
            textField in
            textField.placeholder = placeholder
            textField.secureTextEntry = false
            textField.keyboardAppearance = .Dark
            textField.autocapitalizationType = .Words
            textField.autocorrectionType = .Default
            textField.returnKeyType = .Done
            textField.text = startingText
            
            if forcedInput {
                NSNotificationCenter.defaultCenter().addObserver(self, selector: #selector(self.notificationReceived(_:)), name: UITextFieldTextDidChangeNotification, object: textField)
            }
        }
    }
    
    required init?(coder aDecoder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    override var preferredStyle: UIAlertControllerStyle {
        return .Alert
    }
    
    func notificationReceived(notification: NSNotification) {
        if let textField = notification.object as? UITextField, let emptyText = textField.text?.isEmpty {
            okAction.enabled = !emptyText
        }
    }
}


