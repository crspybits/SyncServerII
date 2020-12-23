
import Foundation
import LoggerAPI
import ServerAccount
import ServerAppleSignInAccount

class AppleServerToServerNotifications : ControllerProtocol {
    let clientId: String
    
    init(clientId: String) {
        self.clientId = clientId
    }
    
    static func setup() -> Bool {
        return true
    }
    
    func process(params:RequestProcessingParameters) {
        guard let request = params.request as? NotificationRequest else {
            let message = "Did not get NotificationRequest."
            Log.error(message)
            params.completion(.failure(.message(message)))
            return
        }
        
        request.getEventFromJWT(clientId: clientId) { result in
            switch result {
            case .success(let claims):
                Log.debug("getEventFromJWT: \(claims)")
                // TODO: Now that we have the event, we need to take some actions in the server if necessary.
                params.completion(.success(NotificationResponse()))

            case .failure(let error):
                let message = "Failed getting event from JWT: \(error)"
                Log.error(message)
                params.completion(.failure(.message(message)))
            }
        }
    }
}
