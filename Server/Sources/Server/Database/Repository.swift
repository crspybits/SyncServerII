//
//  Repository.swift
//  Server
//
//  Created by Christopher Prince on 11/26/16.
//
//

import Foundation

protocol Repository {
    // Create the database table; returns false if there was an error.
    static func create() -> Database.TableCreationResult

}
