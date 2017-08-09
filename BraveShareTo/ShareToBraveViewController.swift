
import UIKit
import Social
import MobileCoreServices

extension NSObject {
    func callSelector(_ selector: Selector, object: AnyObject?, delay: TimeInterval) {
        let delay = delay * Double(NSEC_PER_SEC)
        let time = DispatchTime.now() + Double(Int64(delay)) / Double(NSEC_PER_SEC)
        DispatchQueue.main.asyncAfter(deadline: time, execute: {
            Thread.detachNewThreadSelector(selector, toTarget:self, with: object)
        })
    }
}

class ShareToBraveViewController: SLComposeServiceViewController {

    override func isContentValid() -> Bool {
        return true
    }

    override func didSelectPost() {
        return
    }

    override func configurationItems() -> [Any]! {
        let item: NSExtensionItem = extensionContext!.inputItems[0] as! NSExtensionItem
        let itemProvider: NSItemProvider = item.attachments![0] as! NSItemProvider
        let type = kUTTypeURL as String

        if itemProvider.hasItemConformingToTypeIdentifier(type) {
            itemProvider.loadItem(forTypeIdentifier: type, options: nil, completionHandler: {
                (urlItem, error) in
                guard let url = (urlItem as! URL).absoluteString.addingPercentEncoding(withAllowedCharacters: CharacterSet.alphanumerics),
                    let braveUrl = URL(string: "brave://open-url?url=\(url)") else { return }

                // From http://stackoverflow.com/questions/24297273/openurl-not-work-in-action-extension
                var responder = self as UIResponder?
                while (responder != nil) {
                    if responder!.responds(to: #selector(UIApplication.openURL(_:))) {
                        responder!.callSelector(#selector(UIApplication.openURL(_:)), object: braveUrl as AnyObject, delay: 0)
                    }
                    responder = responder!.next
                }

                DispatchQueue.main.asyncAfter(
                    deadline: DispatchTime.now() + Double(Int64(0.1 * Double(NSEC_PER_SEC))) / Double(NSEC_PER_SEC), execute: { self.cancel() })
            })
        }

        return []
    }

    override func viewDidAppear(_ animated: Bool) {
        // Stop keyboard from showing
        textView.resignFirstResponder()
        textView.isEditable = false

        super.viewDidAppear(animated)
    }

    override func willMove(toParentViewController parent: UIViewController?) {
        view.alpha = 0
    }
}
