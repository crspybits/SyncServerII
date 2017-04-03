//
//  IconCollectionVC.swift
//  SharedImages
//
//  Created by Christopher Prince on 3/10/17.
//  Copyright © 2017 Spastic Muffin, LLC. All rights reserved.
//

import Foundation
import UIKit
import SMCoreLib

class IconCollectionVC : UICollectionViewCell {
    @IBOutlet weak var imageView: UIImageView!
    private var image:Image!
    private weak var syncController:SyncController!

    required public init?(coder aDecoder: NSCoder) {
        super.init(coder: aDecoder)
    }
    
    func setProperties(image:Image, syncController:SyncController) {
        self.image = image
        self.syncController = syncController
        
        let uiImage = UIImage(contentsOfFile: self.image.url!.path!)
        self.imageView.image = uiImage
        
        Log.msg("image.url: \(image.url!.path!)")
        Log.msg("image.uuid: \(image.uuid)")
    }
    
    func remove() {
        // The sync/remote remove must happen before the local remove-- or we lose the reference!
        syncController.remove(image: image)
        
        CoreData.sessionNamed(CoreDataExtras.sessionName).remove(image)
        CoreData.sessionNamed(CoreDataExtras.sessionName).saveContext()
    }
}
