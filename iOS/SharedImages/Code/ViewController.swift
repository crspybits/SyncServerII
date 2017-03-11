//
//  ViewController.swift
//  SharedImages
//
//  Created by Christopher Prince on 3/8/17.
//  Copyright © 2017 Spastic Muffin, LLC. All rights reserved.
//

import UIKit
import SMCoreLib

class ViewController: UIViewController {
    let reuseIdentifier = "ImageIcon"
    var acquireImage:SMAcquireImage!
    var addImageBarButton:UIBarButtonItem!
    var coreDataSource:CoreDataSource!
    
    @IBOutlet weak var collectionView: UICollectionView!
    
    override func viewDidLoad() {
        super.viewDidLoad()
        collectionView.dataSource = self
        
        addImageBarButton = UIBarButtonItem(barButtonSystemItem: .add, target: self, action: #selector(addImageAction))
        self.navigationItem.rightBarButtonItem = addImageBarButton
        
        self.acquireImage = SMAcquireImage(withParentViewController: self)
        self.acquireImage.delegate = self
        
        self.coreDataSource = CoreDataSource(delegate: self)
    }
    
    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        coreDataSource.fetchData()
    }
    
    func addImageAction() {
        self.acquireImage.showAlert(fromBarButton: addImageBarButton)
    }
}

extension ViewController : UICollectionViewDataSource {
    func numberOfSections(in collectionView: UICollectionView) -> Int {
        return 1
    }
    
    func collectionView(_ collectionView: UICollectionView, numberOfItemsInSection section: Int) -> Int {
        return Int(coreDataSource.numberOfRows(inSection: 0))
    }

    func collectionView(_ collectionView: UICollectionView, cellForItemAt indexPath: IndexPath) -> UICollectionViewCell {
        
        let cell = collectionView.dequeueReusableCell(withReuseIdentifier: reuseIdentifier, for: indexPath) as! IconCollectionVC
        
        let imageObj = self.coreDataSource.object(at: indexPath) as! Image
        let image = UIImage(contentsOfFile: imageObj.url!.path!)
        cell.imageView.image = image
        return cell
    }
}

extension ViewController : SMAcquireImageDelegate {
    // Called before the image is acquired to obtain a URL for the image. A file shouldn't exist at this URL yet.
    func smAcquireImageURLForNewImage(_ acquireImage:SMAcquireImage) -> SMRelativeLocalURL {
        return FileExtras().newURLForImage()
    }
    
    // Called after the image is acquired.
    func smAcquireImage(_ acquireImage:SMAcquireImage, newImageURL: SMRelativeLocalURL) {
        let newImage = Image.newObjectAndMakeUUID(makeUUID: true) as! Image
        newImage.url = newImageURL
        CoreData.sessionNamed(CoreDataExtras.sessionName).saveContext()
    }
}

extension ViewController : CoreDataSourceDelegate {
    // This must have sort descriptor(s) because that is required by the NSFetchedResultsController, which is used internally by this class.
    func coreDataSourceFetchRequest(_ cds: CoreDataSource!) -> NSFetchRequest<NSFetchRequestResult>! {
        return Image.fetchRequestForAllObjects()
    }
    
    func coreDataSourceContext(_ cds: CoreDataSource!) -> NSManagedObjectContext! {
        return CoreData.sessionNamed(CoreDataExtras.sessionName).context
    }
    
    // Should return YES iff the context save was successful.
    func coreDataSourceSaveContext(_ cds: CoreDataSource!) -> Bool {
        return CoreData.sessionNamed(CoreDataExtras.sessionName).saveContext()
    }
    
    func coreDataSource(_ cds: CoreDataSource!, objectWasDeleted indexPathOfDeletedObject: IndexPath!) {
        collectionView.deleteItems(at: [indexPathOfDeletedObject as IndexPath])
    }
    
    func coreDataSource(_ cds: CoreDataSource!, objectWasInserted indexPathOfInsertedObject: IndexPath!) {
        collectionView.reloadData()
    }
    
    func coreDataSource(_ cds: CoreDataSource!, objectWasUpdated indexPathOfUpdatedObject: IndexPath!) {
        collectionView.reloadData()
    }
    
    // 5/20/16; Odd. This gets called when an object is updated, sometimes. It may be because the sorting key I'm using in the fetched results controller changed.
    func coreDataSource(_ cds: CoreDataSource!, objectWasMovedFrom oldIndexPath: IndexPath!, to newIndexPath: IndexPath!) {
        collectionView.reloadData()
    }
}

