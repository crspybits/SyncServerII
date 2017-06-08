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
    private var image:Image!
    private weak var syncController:SyncController!

    required public init?(coder aDecoder: NSCoder) {
        super.init(coder: aDecoder)
    }
    
    func setProperties(image:Image, syncController:SyncController) {
        self.image = image
        self.syncController = syncController
        title.text = image.title
    }
    
    override func layoutSubviews() {
        super.layoutSubviews()
        
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
