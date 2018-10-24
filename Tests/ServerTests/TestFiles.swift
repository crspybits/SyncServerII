//
//  TestFiles.swift
//  ServerTests
//
//  Created by Christopher G Prince on 10/23/18.
//

import Foundation
@testable import Server

struct TestFile {
    enum FileContents {
        case string(String)
        case url(URL)
    }
    
    let dropboxCheckSum:String
    let md5CheckSum:String // Google
    let contents: FileContents
    
    func checkSum(type: AccountType) -> String! {
        switch type {
        case .Google:
            return md5CheckSum
        case .Dropbox:
            return dropboxCheckSum
        case .Facebook:
            return nil
        }
    }
    
    static let test1 = TestFile(dropboxCheckSum: "", md5CheckSum: "", contents: .string("Hello World"))
    static let test2 = TestFile(dropboxCheckSum: "", md5CheckSum: "", contents: .string("This is some longer text that I'm typing here and hopefullly I don't get too bored"))

#if os(macOS)
        private static let catFileURL = URL(fileURLWithPath: "/tmp/Cat.jpg")
#else
        private static let catFileURL = URL(fileURLWithPath: "./Resources/Cat.jpg")
#endif
    static let catJpg = TestFile(dropboxCheckSum: "", md5CheckSum: "", contents: .url(catFileURL))
}
