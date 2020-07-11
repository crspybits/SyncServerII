import Foundation
import Server

public class Uploader {
    // Check if there is uploading to do. Uses a lock so it is safe *across* instances of the server. i.e., there will be at most one instance of this running across server instances.
    public func run() {
    }
}
