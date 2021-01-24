
import Foundation
import LoggerAPI
import ServerAccount
import ServerAppleSignInAccount
import ServerShared

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
            case .failure(let error):
                let message = "Failed getting event from JWT: \(error)"
                Log.error(message)
                params.completion(.failure(.message(message)))
                
            case .success(let claims):
                Log.debug("getEventFromJWT: \(claims)")
                
                guard let event = claims.events else {
                    let message = "No event in claims."
                    Log.error(message)
                    params.completion(.failure(.message(message)))
                    return
                }
                
                let appleUserId = event.sub
                let successResponse = NotificationResponse()
                let accountScheme = AccountScheme.appleSignIn
                
                switch event.type {
                case .emailDisabled, .emailEnabled:
                    Log.info("Email event (\(event.type)); no action taken.")
                    params.completion(.success(successResponse))
                    return
                    
                case .accountDelete, .consentRevoked:
                    Log.info("Account deletion event (\(event.type)); deleting user account.")
                }
                
                let userRepoKey = UserRepository.LookupKey.accountTypeInfo(accountType: accountScheme.accountName, credsId: appleUserId)
                let result = params.repos.user.lookup(key: userRepoKey, modelInit: User.init)
                
                switch result {
                case .noObjectFound:
                    let message = "Could not get User object!"
                    Log.error(message)
                    params.completion(.failure(.message(message)))
                    
                case .error(let errorString):
                    let message = "Could not get User model: \(errorString)"
                    Log.error(message)
                    params.completion(.failure(.message(message)))
                
                case .found(let model):
                    guard let userModel = model as? User else {
                        let message = "Could not get User model."
                        Log.error(message)
                        params.completion(.failure(.message(message)))
                        return
                    }

                    UserController.removeUser(repos: params.repos, accountScheme: accountScheme, userId: userModel.userId, successResponseMessage: successResponse, completion: params.completion)
                }
            }
        }
    }
}
