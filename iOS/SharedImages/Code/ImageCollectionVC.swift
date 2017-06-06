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
    private var image:Image!
    private weak var syncController:SyncController!

    required public init?(coder aDecoder: NSCoder) {
        super.init(coder: aDecoder)
    }
    
    func setProperties(image:Image, syncController:SyncController) {
        self.image = image
        self.syncController = syncController
    }
    
    override func layoutSubviews() {
        super.layoutSubviews()
        
        let imageFileName = image.url!.lastPathComponent!
        let iconDirectory = "SmallImages"
        let iconDirectoryURL = FileStorage.url(ofItem: iconDirectory)
        let largeImageDirectoryURL = FileStorage.url(ofItem: FileExtras.defaultDirectoryPath)

        // Need to figure out the size of the icon so we don't distort the aspect ratio. Adapted from https://gist.github.com/tomasbasham/10533743
        let largeImageSize = ImageStorage.size(ofImage: imageFileName, withPath: largeImageDirectoryURL)
        
        let aspectWidth = imageView.frameSize.width / largeImageSize.width
        let aspectHeight = imageView.frameSize.height / largeImageSize.height
        let aspectRatio = min(aspectWidth, aspectHeight)

        let iconSize = CGSize(width: largeImageSize.width * aspectRatio, height: largeImageSize.height * aspectRatio)
        
        let imageIcon = ImageStorage.getImage(imageFileName, of: iconSize, fromIconDirectory: iconDirectoryURL, withLargeImageDirectory: largeImageDirectoryURL)
        
        imageView.image = imageIcon
    }
    
    func remove() {
        // The sync/remote remove must happen before the local remove-- or we lose the reference!
        syncController.remove(image: image)
        
        CoreData.sessionNamed(CoreDataExtras.sessionName).remove(image)
        CoreData.sessionNamed(CoreDataExtras.sessionName).saveContext()
    }
}
