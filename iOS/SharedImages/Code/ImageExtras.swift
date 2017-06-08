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
    
    static func sizeFromImage(image:Image) -> CGSize {
        var originalImageSize = CGSize()

        // Originally, I wasn't storing these sizes, so need to grab & store them here if we can. (Defaults for sizes are -1).
        if image.originalWidth < 0 || image.originalHeight < 0 {
            originalImageSize = ImageExtras.sizeFromFile(url: image.url! as URL)
            image.originalWidth = Float(originalImageSize.width)
            image.originalHeight = Float(originalImageSize.height)
            CoreData.sessionNamed(CoreDataExtras.sessionName).saveContext()
        }
        else {
            originalImageSize.height = CGFloat(image.originalHeight)
            originalImageSize.width = CGFloat(image.originalWidth)
        }
        
        return originalImageSize
    }
    
    // Get the size of the icon without distorting the aspect ratio. Adapted from https://gist.github.com/tomasbasham/10533743
    static func boundingImageSizeFor(originalSize:CGSize, boundingSize:CGSize) -> CGSize {
        let aspectWidth = boundingSize.width / originalSize.width
        let aspectHeight = boundingSize.height / originalSize.height
        let aspectRatio = min(aspectWidth, aspectHeight)

        return CGSize(width: originalSize.width * aspectRatio, height: originalSize.height * aspectRatio)
    }
}
