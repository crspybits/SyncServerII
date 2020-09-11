//
//  PeriodicUploader.swift
//  Server
//
//  Created by Christopher G Prince on 9/9/20.
//

// See https://github.com/SyncServerII/ServerMain/issues/6

import Foundation
import LoggerAPI

class PeriodicUploader {
    var uploader:Uploader!
    let interval: TimeInterval
    let services: UploaderServices
    var repeatingTimer: RepeatingTimer?
    
    // The interval should be long enough that the Uploader completes in that duration.
    init(interval: TimeInterval, services: UploaderServices) {
        self.interval = interval
        self.services = services
        schedule()
    }
    
    func schedule() {
        repeatingTimer = RepeatingTimer(timeInterval: interval)
        repeatingTimer?.eventHandler = { [weak self] in
            guard let self = self else { return }
            
            Log.debug("PeriodicUploader: About to run Uploader")

            self.uploader = Uploader(services: self.services, delegate: nil)

            do {
                try self.uploader.run()
            } catch let error {
                Log.error("\(error)")
            }
            
            self.schedule()
        }
        
        repeatingTimer?.resume()
    }
    
    func reset() {
        Log.debug("PeriodicUploader: Reset")
        
        uploader = nil
        repeatingTimer?.suspend()
        repeatingTimer = nil
        
        schedule()
    }
}
