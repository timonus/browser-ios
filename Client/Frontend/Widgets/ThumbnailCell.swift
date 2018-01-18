/* This Source Code Form is subject to the terms of the Mozilla Public
 * License, v. 2.0. If a copy of the MPL was not distributed with this
 * file, You can obtain one at http://mozilla.org/MPL/2.0/. */

import UIKit
import Shared

struct ThumbnailCellUX {
    // TODO: Clean up unused constants

    /// Ratio of width:height of the thumbnail image.
    static let ImageAspectRatio: Float = 1.0
    static let BorderColor = UIColor.black.withAlphaComponent(0.15)
    static let BorderWidth: CGFloat = 0.5
    static let LabelColor = UIAccessibilityDarkerSystemColorsEnabled() ? UIColor.black : UIColor(rgb: 0x353535)
    static let LabelAlignment: NSTextAlignment = .center
    static let SelectedOverlayColor = UIColor(white: 0.0, alpha: 0.25)
    static let InsetSize: CGFloat = 10
    static let InsetSizeCompact: CGFloat = 3
    static let ImagePaddingWide: CGFloat = 4
    static let ImagePaddingCompact: CGFloat = 2

    // TODO: This is absurd, remove it
    static func insetsForCollectionViewSize(_ size: CGSize, traitCollection: UITraitCollection) -> UIEdgeInsets {
        let largeInsets = UIEdgeInsets(
                top: ThumbnailCellUX.InsetSize,
                left: ThumbnailCellUX.InsetSize,
                bottom: ThumbnailCellUX.InsetSize,
                right: ThumbnailCellUX.InsetSize
            )
        let smallInsets = UIEdgeInsets(
                top: ThumbnailCellUX.InsetSizeCompact,
                left: ThumbnailCellUX.InsetSizeCompact,
                bottom: ThumbnailCellUX.InsetSizeCompact,
                right: ThumbnailCellUX.InsetSizeCompact
            )

        if traitCollection.horizontalSizeClass == .compact {
            return smallInsets
        } else {
            return largeInsets
        }
    }

    // TODO: Remove
    static func imageInsetsForCollectionViewSize(_ size: CGSize, traitCollection: UITraitCollection) -> UIEdgeInsets {
        let largeInsets = UIEdgeInsets(
                top: ThumbnailCellUX.ImagePaddingWide,
                left: ThumbnailCellUX.ImagePaddingWide,
                bottom: ThumbnailCellUX.ImagePaddingWide,
                right: ThumbnailCellUX.ImagePaddingWide
            )

        let smallInsets = UIEdgeInsets(
                top: ThumbnailCellUX.ImagePaddingCompact,
                left: ThumbnailCellUX.ImagePaddingCompact,
                bottom: ThumbnailCellUX.ImagePaddingCompact,
                right: ThumbnailCellUX.ImagePaddingCompact
            )
        if traitCollection.horizontalSizeClass == .compact {
            return smallInsets
        } else {
            return largeInsets // reminder: iphone landscape uses this
        }
    }

    static let LabelInsets = UIEdgeInsetsMake(0, 3, 2, 3)
    static let PlaceholderImage = UIImage(named: "defaultTopSiteIcon")
    static let CornerRadius: CGFloat = 8

    // Make the remove button look 20x20 in size but have the clickable area be 44x44
    static let RemoveButtonSize: CGFloat = 44
    static let RemoveButtonInsets = UIEdgeInsets(top: 11, left: 0, bottom: 11, right: 22)
    static let RemoveButtonAnimationDuration: TimeInterval = 0.4
    static let RemoveButtonAnimationDamping: CGFloat = 0.6

    static let NearestNeighbordScalingThreshold: CGFloat = 24
}

@objc protocol ThumbnailCellDelegate {
    func editThumbnail(_ thumbnailCell: ThumbnailCell)
}

class ThumbnailCell: UICollectionViewCell {
    weak var delegate: ThumbnailCellDelegate?

    var imageInsets: UIEdgeInsets = UIEdgeInsets.zero
    var cellInsets: UIEdgeInsets = UIEdgeInsets.zero

    // TODO: Remove
    var imagePadding: CGFloat = 0

    static func imageWithSize(_ image: UIImage, size:CGSize, maxScale: CGFloat) -> UIImage {
        var scaledImageRect = CGRect.zero;
        var aspectWidth:CGFloat = size.width / image.size.width;
        var aspectHeight:CGFloat = size.height / image.size.height;
        if aspectWidth > maxScale || aspectHeight > maxScale {
            let m = max(maxScale / aspectWidth, maxScale / aspectHeight)
            aspectWidth *= m
            aspectHeight *= m
        }
        let aspectRatio:CGFloat = min(aspectWidth, aspectHeight);
        scaledImageRect.size.width = image.size.width * aspectRatio;
        scaledImageRect.size.height = image.size.height * aspectRatio;
        scaledImageRect.origin.x = (size.width - scaledImageRect.size.width) / 2.0;
        scaledImageRect.origin.y = (size.height - scaledImageRect.size.height) / 2.0;
        UIGraphicsBeginImageContextWithOptions(size, false, 0);
        image.draw(in: scaledImageRect);
        let scaledImage = UIGraphicsGetImageFromCurrentImageContext();
        UIGraphicsEndImageContext();
        return scaledImage!;
    }

    var image: UIImage? = nil {
        didSet {
            struct ContainerSize {
                static var size: CGSize = CGSize.zero
                static func scaledDown() -> CGSize {
                    return CGSize(width: size.width * 0.75, height: size.height * 0.75)
                }
            }

            if imageView.frame.size.width > 0 {
                ContainerSize.size = imageView.frame.size
            }

            if var image = image {
                if image.size.width <= 32 && ContainerSize.size != CGSize.zero {
                    var maxScale = CGFloat(image.size.width < 24 ? 3.0 : 1.5)
                    if ContainerSize.size.width > 170 {
                        // we are on iPad pro. Fragile, but no other way to detect this on simulator.
                        maxScale *= 2.0
                    }
                    image = ThumbnailCell.imageWithSize(image, size: ContainerSize.scaledDown(), maxScale: maxScale)
                    imageView.contentMode = .center
                }
                else if image.size.width > 32 {
                    imageView.contentMode = .scaleAspectFit
                }
                imageView.image = image
            } else {
                imageView.image = ThumbnailCellUX.PlaceholderImage
                imageView.contentMode = .center
            }
        }
    }

    lazy var textLabel: UILabel = {
        let textLabel = UILabel()
        textLabel.setContentHuggingPriority(1000, for: UILayoutConstraintAxis.vertical)
        textLabel.font = DynamicFontHelper.defaultHelper.DefaultSmallFont
        textLabel.textColor = ThumbnailCellUX.LabelColor
        textLabel.textAlignment = ThumbnailCellUX.LabelAlignment
        return textLabel
    }()

    lazy var imageView: UIImageView = {
        let imageView = UIImageView()
        imageView.contentMode = .scaleAspectFit
        imageView.clipsToBounds = true
        imageView.layer.cornerRadius = ThumbnailCellUX.CornerRadius
        imageView.layer.borderColor = ThumbnailCellUX.BorderColor.cgColor
        imageView.layer.minificationFilter = kCAFilterTrilinear
        imageView.layer.magnificationFilter = kCAFilterNearest
        return imageView
    }()


    // TODO: Remove
    lazy var imageWrapper: UIView = {
        let imageWrapper = UIView()
        imageWrapper.layer.cornerRadius = ThumbnailCellUX.CornerRadius
        imageWrapper.clipsToBounds = true
        return imageWrapper
    }()

    lazy var editButton: UIButton = {
        let editButton = UIButton()
        editButton.isExclusiveTouch = true
        let removeButtonImage = UIImage(named: "edit_tile")
        editButton.setImage(removeButtonImage, for: .normal)
        editButton.addTarget(self, action: #selector(ThumbnailCell.editButtonTapped), for: UIControlEvents.touchUpInside)
        editButton.accessibilityLabel = Strings.Edit_Bookmark
        editButton.isHidden = true
        editButton.sizeToFit()
        let xOffset: CGFloat = 5
        let buttonCenterX = floor(editButton.bounds.width/2) + xOffset
        let buttonCenterY = floor(editButton.bounds.height/2)
        editButton.center = CGPoint(x: buttonCenterX, y: buttonCenterY)
        return editButton    }()

    // TODO: Should be no longer needed
    lazy var backgroundImage: UIImageView = {
        let backgroundImage = UIImageView()
        backgroundImage.contentMode = UIViewContentMode.scaleAspectFill
        return backgroundImage
    }()

    // TODO: Remove
    lazy var selectedOverlay: UIView = {
        let selectedOverlay = UIView()
        selectedOverlay.backgroundColor = ThumbnailCellUX.SelectedOverlayColor
        selectedOverlay.isHidden = true
        return selectedOverlay
    }()

    override var isSelected: Bool {
        didSet { updateSelectedHighlightedState() }
    }

    override var isHighlighted: Bool {
        didSet { updateSelectedHighlightedState() }
    }

    override init(frame: CGRect) {
        super.init(frame: frame)

        layer.shouldRasterize = true
        layer.rasterizationScale = UIScreen.main.scale

        isAccessibilityElement = true

        contentView.addSubview(imageView)
        contentView.addSubview(textLabel)
        contentView.addSubview(editButton)

        textLabel.snp.remakeConstraints { make in
            // TODO: relook at insets
            make.left.right.equalTo(self.contentView).inset(ThumbnailCellUX.LabelInsets)
            make.top.equalTo(imageView.snp.bottom).offset(5)
        }

        // Prevents the textLabel from getting squished in relation to other view priorities.
        textLabel.setContentCompressionResistancePriority(1000, for: UILayoutConstraintAxis.vertical)

        NotificationCenter.default.addObserver(self, selector: #selector(showEditMode), name: NotificationThumbnailEditOn,
                                               object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(hideEditMode), name: NotificationThumbnailEditOff,
                                               object: nil)
    }

    deinit {
        NotificationCenter.default.removeObserver(self, name: NotificationThumbnailEditOn, object: nil)
        NotificationCenter.default.removeObserver(self, name: NotificationThumbnailEditOff, object: nil)
    }

    func showEditMode() {
        toggleRemoveButton(true)
    }

    func hideEditMode() {
        toggleRemoveButton(false)
    }

    required init?(coder aDecoder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func prepareForReuse() {
        super.prepareForReuse()
        backgroundImage.image = nil
        editButton.isHidden = true
        showBorder(false)
        backgroundColor = UIColor.clear
        textLabel.font = DynamicFontHelper.defaultHelper.DefaultSmallFont
        textLabel.textColor = PrivateBrowsing.singleton.isOn ? UIColor(rgb: 0xDBDBDB) : UIColor(rgb: 0x2D2D2D)
        // FIXME: Why is there image and imageView.image? First one must be some legacy code but I'm not sure 100
        imageView.backgroundColor = UIColor.clear
        imageView.image = nil
    }

    fileprivate func updateSelectedHighlightedState() {
        let activated = isSelected || isHighlighted
        self.imageView.alpha = activated ? 0.7 : 1.0
    }

    func editButtonTapped() {
        delegate?.editThumbnail(self)
    }

    func toggleRemoveButton(_ show: Bool) {
        // Only toggle if we change state
        if editButton.isHidden != show {
            return
        }

        if show {
            editButton.isHidden = false
        }

        let scaleTransform = CGAffineTransform(scaleX: 0.01, y: 0.01)
        editButton.transform = show ? scaleTransform : CGAffineTransform.identity
        UIView.animate(withDuration: ThumbnailCellUX.RemoveButtonAnimationDuration,
                       delay: 0,
                       usingSpringWithDamping: ThumbnailCellUX.RemoveButtonAnimationDamping,
                       initialSpringVelocity: 0,
                       options: UIViewAnimationOptions.allowUserInteraction,
                       animations: {
                        self.editButton.transform = show ? CGAffineTransform.identity : scaleTransform
        }, completion: { _ in
            if !show {
                self.editButton.isHidden = true
            }
        })
    }

    func showBorder(_ show: Bool) {
        imageView.layer.borderWidth = show ? ThumbnailCellUX.BorderWidth : 0
    }

    /**
     Updates the insets and padding of the cell based on the size of the container collection view

     - parameter size: Size of the container collection view
     */
    func updateLayoutForCollectionViewSize(_ size: CGSize, traitCollection: UITraitCollection, forSuggestedSite: Bool) {

        // Find out if our image is going to have fractional pixel width.
        // If so, we inset by a tiny extra amount to get it down to an integer for better
        // image scaling.
        let parentWidth = self.imageWrapper.frame.width
        let width = (parentWidth - imagePadding)
        let fractionalW = width - floor(width)
        let additionalW = fractionalW / 2

        // TODO: Should not remade on every layout call
        imageView.snp.remakeConstraints { make in
            make.top.equalTo(self.contentView).inset(8)
            make.right.left.equalTo(self.contentView).inset(16 + additionalW)
            make.height.equalTo(imageView.snp.width)
        }
        imageView.setNeedsUpdateConstraints()
    }
}
