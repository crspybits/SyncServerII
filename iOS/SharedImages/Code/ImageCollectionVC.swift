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
        title?.text = "Bushrod Thomas from Florida"
    }
    
    static let iconDirectory = "SmallImages"
    static let iconDirectoryURL = FileStorage.url(ofItem: iconDirectory)
    static let largeImageDirectoryURL = FileStorage.url(ofItem: FileExtras.defaultDirectoryPath)
    static func imageFileName(_ image:Image) -> String {
        return image.url!.lastPathComponent!
    }

    // Get the size of the icon without distorting the aspect ratio. Adapted from https://gist.github.com/tomasbasham/10533743
    static func imageSize(image:Image, boundingSize:CGSize) -> CGSize {

        let largeImageSize = ImageStorage.size(ofImage: imageFileName(image), withPath: largeImageDirectoryURL)
        
        let aspectWidth = boundingSize.width / largeImageSize.width
        let aspectHeight = boundingSize.height / largeImageSize.height
        let aspectRatio = min(aspectWidth, aspectHeight)

        return CGSize(width: largeImageSize.width * aspectRatio, height: largeImageSize.height * aspectRatio)
    }
    
    override func layoutSubviews() {
        super.layoutSubviews()
        
        let iconSize = ImageCollectionVC.imageSize(image: image, boundingSize: imageView.frameSize)
        
        imageView.image = ImageStorage.getImage(ImageCollectionVC.imageFileName(image), of: iconSize, fromIconDirectory: ImageCollectionVC.iconDirectoryURL, withLargeImageDirectory: ImageCollectionVC.largeImageDirectoryURL)
    }
    
    func remove() {
        // The sync/remote remove must happen before the local remove-- or we lose the reference!
        syncController.remove(image: image)
        
        CoreData.sessionNamed(CoreDataExtras.sessionName).remove(image)
        CoreData.sessionNamed(CoreDataExtras.sessionName).saveContext()
    }
}
