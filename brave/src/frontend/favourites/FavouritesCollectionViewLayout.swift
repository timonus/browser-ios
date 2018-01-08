/* This Source Code Form is subject to the terms of the Mozilla Public License, v. 2.0. If a copy of the MPL was not distributed with this file, You can obtain one at http://mozilla.org/MPL/2.0/. */

import UIKit
import Shared

// TODO: A simpler flow layout is currently used for top sites,
// this class will be probably deleted after new topsites logic is fully implemented.
class FavouritesCollectionViewLayout: UICollectionViewLayout {

    var thumbnailCount: Int {
        assertIsMainThread("layout.thumbnailCount interacts with UIKit components - cannot call from background thread.")
        let dataSource = self.collectionView?.dataSource as? FavouritesDataSource

        return dataSource?.favourites.count ?? 0
    }

    fileprivate var thumbnailRows: Int {
        assert(Thread.isMainThread, "Interacts with UIKit components - not thread-safe.")
        let countDouble = Double(thumbnailCount)
        let colsDouble = Double(thumbnailCols)
        let rowsDouble = countDouble / colsDouble

        return Int(rowsDouble.rounded(.up))
    }

    fileprivate var thumbnailCols: Int {
        assert(Thread.isMainThread, "Interacts with UIKit components - not thread-safe.")

        let size = collectionView?.bounds.size ?? CGSize.zero
        let traitCollection = collectionView!.traitCollection
        var cols = 0
        if traitCollection.horizontalSizeClass == .compact {
            // Landscape iPhone
            if traitCollection.verticalSizeClass == .compact {
                cols = 5
            }
                // Split screen iPad width
            else if size.widthLargerOrEqualThanHalfIPad() {
                cols = 4
            }
                // iPhone portrait
            else {
                cols = 3
            }
        } else {
            // Portrait iPad
            if size.height > size.width {
                cols = 4;
            }
                // Landscape iPad
            else {
                cols = 5;
            }
        }
        return cols + 1
    }

    fileprivate var width: CGFloat {
        assertIsMainThread("layout.width interacts with UIKit components - cannot call from background thread.")
        return self.collectionView?.frame.width ?? 0
    }

    // The width and height of the thumbnail here are the width and height of the tile itself, not the image inside the tile.
    fileprivate var thumbnailWidth: CGFloat {
        assertIsMainThread("layout.thumbnailWidth interacts with UIKit components - cannot call from background thread.")

        let size = collectionView?.bounds.size ?? CGSize.zero
        let insets = ThumbnailCellUX.insetsForCollectionViewSize(size,
                                                                 traitCollection:  collectionView!.traitCollection)

        print("bxx \(floor(width - insets.left - insets.right) / CGFloat(thumbnailCols))")
        return floor(width - insets.left - insets.right) / CGFloat(thumbnailCols)
    }
    // The tile's height is determined the aspect ratio of the thumbnails width. We also take into account
    // some padding between the title and the image.
    fileprivate var thumbnailHeight: CGFloat {
        assertIsMainThread("layout.thumbnailHeight interacts with UIKit components - cannot call from background thread.")

        return floor(thumbnailWidth / (CGFloat(ThumbnailCellUX.ImageAspectRatio) - 0.1))
    }

    // Used to calculate the height of the list.
    fileprivate var count: Int {
        if let dataSource = self.collectionView?.dataSource as? FavouritesDataSource {
            return dataSource.collectionView(self.collectionView!, numberOfItemsInSection: 0)
        }
        return 0
    }

    fileprivate var topSectionHeight: CGFloat {
        let maxRows = ceil(Float(count) / Float(thumbnailCols))
        let rows = min(Int(maxRows), thumbnailRows)
        let size = collectionView?.bounds.size ?? CGSize.zero
        let insets = ThumbnailCellUX.insetsForCollectionViewSize(size,
                                                                 traitCollection:  collectionView!.traitCollection)
        print("bxx top section: \(thumbnailHeight * CGFloat(rows) + insets.top + insets.bottom)")
        return thumbnailHeight * CGFloat(rows) + insets.top + insets.bottom
    }

    override var collectionViewContentSize : CGSize {
        if count <= thumbnailCount {
            return CGSize(width: width, height: topSectionHeight)
        }

        let bottomSectionHeight = CGFloat(count - thumbnailCount) * UIConstants.DefaultRowHeight + 300
        let size = CGSize(width: width, height: topSectionHeight + bottomSectionHeight)
        return size
    }

    fileprivate var layoutAttributes:[UICollectionViewLayoutAttributes]?

    override func prepare() {
        var layoutAttributes = [UICollectionViewLayoutAttributes]()
        for section in 0..<(self.collectionView?.numberOfSections ?? 0) {
            for item in 0..<(self.collectionView?.numberOfItems(inSection: section) ?? 0) {
                let indexPath = IndexPath(item: item, section: section)
                guard let attrs = self.layoutAttributesForItem(at: indexPath) else { continue }
                layoutAttributes.append(attrs)
            }
        }
        self.layoutAttributes = layoutAttributes
    }

    override func layoutAttributesForElements(in rect: CGRect) -> [UICollectionViewLayoutAttributes]? {
        var attrs = [UICollectionViewLayoutAttributes]()
        if let layoutAttributes = self.layoutAttributes {
            for attr in layoutAttributes {
                if rect.intersects(attr.frame) {
                    attrs.append(attr)
                }
            }
        }

        return attrs
    }

    override func layoutAttributesForItem(at indexPath: IndexPath) -> UICollectionViewLayoutAttributes? {
        let attr = UICollectionViewLayoutAttributes(forCellWith: indexPath)

        // Set the top thumbnail frames.
        let row = floor(Double(indexPath.item / thumbnailCols))
        let col = indexPath.item % thumbnailCols
        let size = collectionView?.bounds.size ?? CGSize.zero
        let insets = ThumbnailCellUX.insetsForCollectionViewSize(size,
                                                                 traitCollection:  collectionView!.traitCollection)
        let x = insets.left + thumbnailWidth * CGFloat(col)
        let y = insets.top + CGFloat(row) * thumbnailHeight
        attr.frame = CGRect(x: ceil(x), y: ceil(y), width: thumbnailWidth, height: thumbnailHeight)

        return attr
    }
}
