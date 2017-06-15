//
//  ImageCollectionVC.swift
//  SharedImages
//
//  Created by Christopher Prince on 3/10/17.
//  Copyright © 2017 Spastic Muffin, LLC. All rights reserved.
//

import Foundation
import UIKit
import SMCoreLib

class ImageCollectionVC : UICollectionViewCell {
    @IBOutlet weak var imageView: UIImageView!
    @IBOutlet weak var title: UILabel!
    private(set) var image:Image!
    private(set) weak var syncController:SyncController!

    required public init?(coder aDecoder: NSCoder) {
        super.init(coder: aDecoder)
    }
    
    func setProperties(image:Image, syncController:SyncController) {
        self.image = image
        self.syncController = syncController
        title.text = image.title
    }
    
    // I had problems knowing when the cell was sized correctly so that I could call `ImageStorage.getImage`. It turns out `layoutSubviews` is not the right place. And neither is `setProperties` (which gets called by cellForItemAt). When the UICollectionView is first displayed, I get small sizes (less than 1/2 of correct sizes) at least on iPad. Odd.
    func willDisplay() {
        // For some reason, when I get here, the cell is sized correctly, but it's subviews are not. And more specifically, the image view subview is not sized correctly all the time. And since I'm basing my image fetch/resize on the image view size, I need it correctly sized right now.
        layoutIfNeeded()
        
        let originalSize = ImageExtras.sizeFromImage(image:image)
        let smallerSize = ImageExtras.boundingImageSizeFor(originalSize: originalSize, boundingSize: imageView.frameSize)
        
        imageView.image = ImageStorage.getImage(ImageExtras.imageFileName(url: image.url! as URL), of: smallerSize, fromIconDirectory: ImageExtras.iconDirectoryURL, withLargeImageDirectory: ImageExtras.largeImageDirectoryURL)
    }
    
    func remove() {
        // The sync/remote remove must happen before the local remove-- or we lose the reference!
        syncController.remove(image: image)
        
        CoreData.sessionNamed(CoreDataExtras.sessionName).remove(image)
        CoreData.sessionNamed(CoreDataExtras.sessionName).saveContext()
    }
}
