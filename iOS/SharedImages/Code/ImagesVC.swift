//
//  ImagesVC.swift
//  SharedImages
//
//  Created by Christopher Prince on 3/8/17.
//  Copyright © 2017 Spastic Muffin, LLC. All rights reserved.
//

import UIKit
import SMCoreLib
import SyncServer

class ImagesVC: UIViewController {
    let reuseIdentifier = "ImageIcon"
    var acquireImage:SMAcquireImage!
    var addImageBarButton:UIBarButtonItem!
    var coreDataSource:CoreDataSource!
    var syncController = SyncController()
    
    // To enable pulling down on the table view to do a sync with server.
    var refreshControl:ODRefreshControl!
    
    let spinner = SyncSpinner(frame: CGRect(x: 0, y: 0, width: 25, height: 25))
    var barButtonSpinner:UIBarButtonItem!

    @IBOutlet weak var collectionView: UICollectionView!
    
    var timeThatSpinnerStarts:CFTimeInterval!
    
    override func viewDidLoad() {
        super.viewDidLoad()
        collectionView.dataSource = self
        
        barButtonSpinner = UIBarButtonItem(customView: spinner)
        navigationItem.leftBarButtonItem = barButtonSpinner
        let tapGesture = UITapGestureRecognizer(target: self, action: #selector(spinnerTapGestureAction))
        self.spinner.addGestureRecognizer(tapGesture)
        
        addImageBarButton = UIBarButtonItem(barButtonSystemItem: .add, target: self, action: #selector(addImageAction))
        navigationItem.rightBarButtonItem = addImageBarButton
        
        acquireImage = SMAcquireImage(withParentViewController: self)
        acquireImage.delegate = self
        
        coreDataSource = CoreDataSource(delegate: self)
        
        syncController.delegate = self
        
        refreshControl = ODRefreshControl(in: collectionView)
        
        // A bit of a hack because the refresh control was appearing too high
        refreshControl.yOffset = -(navigationController!.navigationBar.frameHeight + UIApplication.shared.statusBarFrame.height)
        
        // I like the "tear drop" pull down, but don't want the activity indicator.
        refreshControl.activityIndicatorViewColor = UIColor.clear
        
        refreshControl.addTarget(self, action: #selector(refresh), for: .valueChanged)
        
        collectionView.alwaysBounceVertical = true
    }
    
    @objc private func refresh() {
        self.refreshControl.endRefreshing()
        SyncServer.session.sync()
    }
    
    // Enable a reset from error when needed.
    @objc private func spinnerTapGestureAction() {
        Log.msg("spinner tapped")
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        coreDataSource.fetchData()
    }
    
    func addImageAction() {
        self.acquireImage.showAlert(fromBarButton: addImageBarButton)
    }
    
    @discardableResult
    func addLocalImage(newImageURL: SMRelativeLocalURL, mimeType:String) -> Image {
        let newImage = Image.newObjectAndMakeUUID(makeUUID: true) as! Image
        newImage.url = newImageURL
        newImage.mimeType = mimeType
        CoreData.sessionNamed(CoreDataExtras.sessionName).saveContext()
        
        return newImage
    }
    
    func removeLocalImage(uuid:String) {
        guard let image = Image.fetchObjectWithUUID(uuid: uuid) else {
            Log.error("Cannot find image with UUID: \(uuid)")
            return
        }
        
        CoreData.sessionNamed(CoreDataExtras.sessionName).remove(image)
    }
}

extension ImagesVC : UICollectionViewDataSource {
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

extension ImagesVC : SMAcquireImageDelegate {
    // Called before the image is acquired to obtain a URL for the image. A file shouldn't exist at this URL yet.
    func smAcquireImageURLForNewImage(_ acquireImage:SMAcquireImage) -> SMRelativeLocalURL {
        return FileExtras().newURLForImage()
    }
    
    // Called after the image is acquired.
    func smAcquireImage(_ acquireImage:SMAcquireImage, newImageURL: SMRelativeLocalURL, mimeType:String) {
        let newImage = addLocalImage(newImageURL:newImageURL, mimeType:mimeType)
        syncController.add(image: newImage)
    }
}

extension ImagesVC : CoreDataSourceDelegate {
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

extension ImagesVC : SyncControllerDelegate {
    func addLocalImage(syncController:SyncController, url:SMRelativeLocalURL, uuid:String, mimeType:String) {
        addLocalImage(newImageURL: url, mimeType: mimeType)
    }
    
    func removeLocalImage(syncController:SyncController, uuid:String) {
        removeLocalImage(uuid: uuid)
    }
    
    func syncEvent(syncController:SyncController, event:SyncControllerEvent) {
        switch event {
        case .syncStarted:
            if !self.spinner.animating {
                timeThatSpinnerStarts = CFAbsoluteTimeGetCurrent()
                self.spinner.start()
            }
            
        //case .NonRecoverableError, .InternalError:
        //    self.spinner.stop(withBackgroundColor: .Red)
            
        case .syncDone:
            // If we don't let the spinner show for a minimum amount of time, it looks odd.
            let minimumDuration:CFTimeInterval = 2
            let difference:CFTimeInterval = CFAbsoluteTimeGetCurrent() - timeThatSpinnerStarts
            if difference > minimumDuration {
                self.spinner.stop()
            }
            else {
                let waitingTime = minimumDuration - difference
                
                TimedCallback.withDuration(Float(waitingTime)) {
                    self.spinner.stop()
                }
            }
        }
        
        self.spinner.setNeedsLayout()
    }
}
