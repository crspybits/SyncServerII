//
//  ImageExtras.swift
//  SharedImages
//
//  Created by Christopher Prince on 6/6/17.
//  Copyright © 2017 Spastic Muffin, LLC. All rights reserved.
//

import Foundation
import SMCoreLib

class ImageExtras {
    static let iconDirectory = "SmallImages"
    static let iconDirectoryURL = FileStorage.url(ofItem: iconDirectory)
    static let largeImageDirectoryURL = FileStorage.url(ofItem: FileExtras.defaultDirectoryPath)

    static let appMetaDataTitleKey = "title"
    
    static func imageFileName(url:URL) -> String {
        return url.lastPathComponent
    }
    
    static func sizeFromFile(url:URL) -> CGSize {
        return ImageStorage.size(ofImage: imageFileName(url:url), withPath: largeImageDirectoryURL)
    }
    
    // Get the size of the icon without distorting the aspect ratio. Adapted from https://gist.github.com/tomasbasham/10533743
    static func boundingImageSizeFor(originalSize:CGSize, boundingSize:CGSize) -> CGSize {
        let aspectWidth = boundingSize.width / originalSize.width
        let aspectHeight = boundingSize.height / originalSize.height
        let aspectRatio = min(aspectWidth, aspectHeight)

        return CGSize(width: originalSize.width * aspectRatio, height: originalSize.height * aspectRatio)
    }

    static func removeLocalImage(uuid:String) {
        guard let image = Image.fetchObjectWithUUID(uuid: uuid) else {
            Log.error("Cannot find image with UUID: \(uuid)")
            return
        }
        
        CoreData.sessionNamed(CoreDataExtras.sessionName).remove(image)
        CoreData.sessionNamed(CoreDataExtras.sessionName).saveContext()
    }
}
