import Foundation
import UIKit


/// Wrangles attachment layout and exclusion paths for the specified UITextView.
///
@objc public class WPTextAttachmentManager : NSObject
{
    private let attributeAttachmentName = "NSAttachment" // HACK: DTCoreText hijacks NSAttachmentAttributeName.
    private var kvoContext = 0
    private let attributedTextKey = "attributedText"

    public var attachments = [WPTextAttachment]()
    var attachmentViews = [String: WPTextAttachmentView]()
    public var delegate: WPTextAttachmentManagerDelegate?
    private(set) public var textView: UITextView

    var layoutManager: NSLayoutManager {
        return textView.layoutManager
    }


    /// Cleans up KVO
    ///
    deinit {
        textView.removeObserver(self, forKeyPath: attributedTextKey)
    }


    /// Designaged initializer.
    ///
    /// - Parameters:
    ///     - textView: The UITextView to manage attachment layout.
    ///     - delegate: The delegate who will provide the UIViews used as content represented by WPTextAttachments in the UITextView's NSAttributedString.
    ///
    public init(textView: UITextView, delegate: WPTextAttachmentManagerDelegate) {
        self.textView = textView
        self.delegate = delegate

        super.init()

        setupManager()
    }


    /// Watches for changes in the textView's attributedText.
    ///
    public override func observeValueForKeyPath(keyPath: String?, ofObject object: AnyObject?, change: [String: AnyObject]?, context: UnsafeMutablePointer<Void>) {
        if context != &kvoContext ||
            keyPath == nil ||
            attributedTextKey != keyPath! ||
            textView != object as? UITextView
        {
            super.observeValueForKeyPath(keyPath, ofObject: object, change: change, context: context)
            return
        }

        enumerateAttachments()
    }


    /// Initial setup.  Should only be called once during init.
    ///
    private func setupManager() {
        textView.addObserver(self, forKeyPath: attributedTextKey, options: .New, context: &kvoContext)
        layoutManager.delegate = self

        enumerateAttachments()
    }


    /// Returns the custom view for the specified WPTextAttachment or nil if not found.
    ///
    /// - Parameters:
    ///     - attachment: The WPTextAttachment
    ///
    /// - Returns: A UIView optional
    ///
    public func viewForAttachment(attachment: WPTextAttachment) -> UIView? {
        return attachmentViews[attachment.identifier]?.view
    }


    /// Updates the layout of any custom attachment views.  Call this method after
    /// making changes to the alignment or size of an attachment's custom view,
    /// or after updating an attachment's `image` property.
    ///
    public func layoutAttachmentViews() {
        // Guard for paranoia
        guard let textStorage = layoutManager.textStorage else {
            print("Unable to layout attachment views. No NSTextStorage.")
            return
        }

        // Now do the update.
        textStorage.enumerateAttribute(attributeAttachmentName,
            inRange: NSMakeRange(0, textStorage.length),
            options: [],
            usingBlock: { (object: AnyObject?, range: NSRange, stop: UnsafeMutablePointer<ObjCBool>) in
                guard let attachment = object as? WPTextAttachment else {
                    return
                }
                layoutAttachmentViewForAttachment(attachment, atRange: range)
        })
    }


    /// Updates the layout of the attachment view for the specified attachment by
    /// creating a new exclusion path for the view based on the location of the
    /// specified attachment, and the frame and alignmnent of the view.
    ///
    /// - Parameters:
    ///     - attachment: The WPTextAttachment
    ///     - range: The range of the WPTextAttachment in the textView's NSTextStorage
    ///
    private func layoutAttachmentViewForAttachment(attachment: WPTextAttachment, atRange range: NSRange) {
        guard let attachmentView = attachmentViews[attachment.identifier] else {
            return
        }

        attachmentView.view.frame = textView.frameForTextInRange(range)

        // Always ensure layout after updating
        layoutManager.ensureLayoutForTextContainer(textView.textContainer)
    }


    /// Called initially during the initial set up of the manager, and whenever
    /// the UITextView's attributedText property changes.
    /// After resetting the attachment manager, this method loops over any
    /// WPTextAttachments found in textStorage and asks the delegate for a
    /// custom view for the attachment.
    ///
    private func enumerateAttachments() {
        resetAttachmentManager()

        // Safety new
        guard let textStorage = layoutManager.textStorage else {
            return
        }

        layoutManager.textStorage?.enumerateAttribute(attributeAttachmentName,
            inRange: NSMakeRange(0, textStorage.length),
            options: [],
            usingBlock: { (object: AnyObject?, range: NSRange, stop: UnsafeMutablePointer<ObjCBool>) in
                guard let attachment = object as? WPTextAttachment else {
                    return
                }
                attachments.append(attachment)

                if let view = delegate?.attachmentManager(self, viewForAttachment: attachment) {
                    attachmentViews[attachment.identifier] = WPTextAttachmentView(view: view, identifier: attachment.identifier, exclusionPath: nil)
                    textView.addSubview(view)
                }
        })

        layoutAttachmentViews()
    }


    /// Resets the attachment manager. Any custom views for WPTextAttachments are
    /// removed from the UITextView, their exclusion paths are removed from
    /// textStorage.
    ///
    private func resetAttachmentManager() {
        for (_, attachmentView) in attachmentViews {
            attachmentView.view.removeFromSuperview()
        }
        attachmentViews.removeAll()
        attachments.removeAll()
    }
}


/// A UITextView does not register as delegate to its NSLayoutManager so the
/// WPTextAttachmentManager does in order to be notified of any changes to the size
/// of the UITextView's textContainer.
///
extension WPTextAttachmentManager: NSLayoutManagerDelegate
{
    /// When the size of an NSTextContainer managed by the NSLayoutManager changes
    /// this method updates the size of any custom views for WPTextAttachments,
    /// then lays out the attachment views.
    ///
    public func layoutManager(layoutManager: NSLayoutManager, textContainer: NSTextContainer, didChangeGeometryFromSize oldSize: CGSize) {
        layoutAttachmentViews()
    }
}


/// A WPTextAttachmentManagerDelegate provides custom views for WPTextAttachments to
/// its WPTextAttachmentManager.
///
@objc public protocol WPTextAttachmentManagerDelegate: NSObjectProtocol
{
    /// Delegates must implement this method and return either a UIView or nil for
    /// the specified WPTextAttachment.
    ///
    /// - Parameters:
    ///     - attachmentManager: The WPTextAttachmentManager.
    ///     - attachment: The WPTextAttachment
    ///
    /// - Returns: A UIView to represent the specified WPTextAttachment or nil.
    ///
    func attachmentManager(attachmentManager:WPTextAttachmentManager, viewForAttachment attachment:WPTextAttachment) -> UIView?
}


/// A convenience class for grouping a custom view with its attachment and
/// exclusion path.
///
class WPTextAttachmentView {
    var view: UIView
    var identifier: String
    var exclusionPath: UIBezierPath?

    init(view: UIView, identifier:String, exclusionPath: UIBezierPath?) {
        self.view = view
        self.identifier = identifier
        self.exclusionPath = exclusionPath
    }
}