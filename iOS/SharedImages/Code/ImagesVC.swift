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
        collectionView.delegate = self
  
        // Spinner that shows when syncing
        barButtonSpinner = UIBarButtonItem(customView: spinner)
        navigationItem.leftBarButtonItem = barButtonSpinner
        let tapGesture = UITapGestureRecognizer(target: self, action: #selector(spinnerTapGestureAction))
        self.spinner.addGestureRecognizer(tapGesture)
        
        // Adding images
        addImageBarButton = UIBarButtonItem(barButtonSystemItem: .add, target: self, action: #selector(addImageAction))
        navigationItem.rightBarButtonItem = addImageBarButton
        setAddButtonState()
        
        acquireImage = SMAcquireImage(withParentViewController: self)
        acquireImage.delegate = self
        
        coreDataSource = CoreDataSource(delegate: self)
        syncController.delegate = self
        
        // To manually refresh-- pull down on collection view.
        refreshControl = ODRefreshControl(in: collectionView)
        
        // A bit of a hack because the refresh control was appearing too high
        refreshControl.yOffset = -(navigationController!.navigationBar.frameHeight + UIApplication.shared.statusBarFrame.height)
        
        // I like the "tear drop" pull down, but don't want the activity indicator.
        refreshControl.activityIndicatorViewColor = UIColor.clear
        
        refreshControl.addTarget(self, action: #selector(refresh), for: .valueChanged)
        
        // Long press on image to delete.
        collectionView.alwaysBounceVertical = true
        let imageDeletionLongPress = UILongPressGestureRecognizer(target: self, action: #selector(imageDeletionLongPressAction(gesture:)))
        imageDeletionLongPress.delaysTouchesBegan = true
        collectionView?.addGestureRecognizer(imageDeletionLongPress)
        collectionView?.delegate = self
        
        // A label and a means to do a consistency check.
        let titleLabel = UILabel()
        titleLabel.text = "Shared Images"
        titleLabel.sizeToFit()
        navigationItem.titleView = titleLabel
        let lp = UILongPressGestureRecognizer(target: self, action: #selector(consistencyCheckAction(gesture:)))
        titleLabel.addGestureRecognizer(lp)
        titleLabel.isUserInteractionEnabled = true
    }
    
    func setAddButtonState() {
        switch SignInVC.sharingPermission {
        case .some(.admin), .some(.write), .none: // .none means this is not a sharing user.
            addImageBarButton?.isEnabled = true
            
        case .some(.read):
            addImageBarButton?.isEnabled = false
        }
    }
    
    @objc private func consistencyCheckAction(gesture : UILongPressGestureRecognizer!) {
        if gesture.state != .ended {
            return
        }
        
        let uuids = Image.fetchAll().map { $0.uuid! }
        SyncServer.session.consistencyCheck(localFiles: uuids, repair: false) { error in
        }
    }
    
    @objc private func imageDeletionLongPressAction(gesture : UILongPressGestureRecognizer!) {
        if gesture.state != .ended {
            return
        }
        
        let p = gesture.location(in: self.collectionView)

        // TODO: *2* Confirm the deletion with the user.
        
        if let indexPath = collectionView.indexPathForItem(at: p) {
            let cell = self.collectionView.cellForItem(at: indexPath) as! ImageCollectionVC
            cell.remove()
        } else {
            Log.msg("couldn't find index path")
        }
    }
    
    @objc private func refresh() {
        self.refreshControl.endRefreshing()
        syncController.sync()
    }
    
    // Enable a reset from error when needed.
    @objc private func spinnerTapGestureAction() {
        Log.msg("spinner tapped")
        refresh()
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        coreDataSource.fetchData()
    }
    
    func addImageAction() {
        self.acquireImage.showAlert(fromBarButton: addImageBarButton)
    }
    
    @discardableResult
    func addLocalImage(newImageURL: SMRelativeLocalURL, mimeType:String, uuid:String? = nil) -> Image {
        var newImage:Image!
        
        if uuid == nil {
            newImage = Image.newObjectAndMakeUUID(makeUUID: true) as! Image
        }
        else {
            newImage = Image.newObjectAndMakeUUID(makeUUID: false) as! Image
            newImage.uuid = uuid
        }
        
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

extension ImagesVC : UICollectionViewDelegate {
    func collectionView(_ collectionView: UICollectionView, didSelectItemAt indexPath: IndexPath) {
        let largeImages = storyboard!.instantiateViewController(withIdentifier: "LargeImages") as! LargeImages
        largeImages.startItem = indexPath.item
        largeImages.syncController = syncController
        navigationController!.pushViewController(largeImages, animated: true)
    }
}

// MARK: UICollectionViewDataSource
extension ImagesVC : UICollectionViewDataSource {
    func numberOfSections(in collectionView: UICollectionView) -> Int {
        return 1
    }
    
    func collectionView(_ collectionView: UICollectionView, numberOfItemsInSection section: Int) -> Int {
        return Int(coreDataSource.numberOfRows(inSection: 0))
    }

    func collectionView(_ collectionView: UICollectionView, cellForItemAt indexPath: IndexPath) -> UICollectionViewCell {
        
        let cell = collectionView.dequeueReusableCell(withReuseIdentifier: reuseIdentifier, for: indexPath) as! ImageCollectionVC
        cell.setProperties(image: self.coreDataSource.object(at: indexPath) as! Image, syncController: syncController)
        
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
        // We're making an image that the user of the app added-- we'll generate a new UUID.
        let newImage = addLocalImage(newImageURL:newImageURL, mimeType:mimeType)
        
        // Sync this new image with the server.
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
        // We're making an image for which there is already a UUID on the server.
        addLocalImage(newImageURL: url, mimeType: mimeType, uuid:uuid)
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
            
        case .syncError:
            self.spinner.stop(withBackgroundColor: .red)
        }
        
        self.spinner.setNeedsLayout()
    }
}

extension ImagesVC : UICollectionViewDelegateFlowLayout {
    func collectionView(_ collectionView: UICollectionView, layout collectionViewLayout: UICollectionViewLayout, sizeForItemAt indexPath: IndexPath) -> CGSize {
        let size = collectionView.frame.width * 0.20
        return CGSize(width: size, height: size)
    }
}

extension ImagesVC : TabControllerNavigation {
    func tabBarViewControllerWasSelected() {
        setAddButtonState()
    }
}
