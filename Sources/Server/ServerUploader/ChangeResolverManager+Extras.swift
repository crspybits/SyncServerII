//
//  ChangeResolverManager+Extras.swift
//  Server
//
//  Created by Christopher G Prince on 7/12/20.
//

import Foundation
import ChangeResolvers

extension ChangeResolverManager {
    func setupResolvers() throws {
        try addResolverType(CommentFile.self)
    }
}
