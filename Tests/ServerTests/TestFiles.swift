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
    
    static let test1 = TestFile(dropboxCheckSum: "42a873ac3abd02122d27e80486c6fa1ef78694e8505fcec9cbcc8a7728ba8949", md5CheckSum: "b10a8db164e0754105b7a99be72e3fe5", contents: .string("Hello World"))
    static let test2 = TestFile(dropboxCheckSum: "3e1c5665be7f2f5552efb9fd93df8fe9d58c54619fefe1a5b474e38464391011", md5CheckSum: "a9d2b23e3001e558213c4ee056f31ba1", contents: .string("This is some longer text that I'm typing here and hopefullly I don't get too bored"))

#if os(macOS)
        private static let catFileURL = URL(fileURLWithPath: "/tmp/Cat.jpg")
#else
        private static let catFileURL = URL(fileURLWithPath: "./Resources/Cat.jpg")
#endif

    static let catJpg = TestFile(dropboxCheckSum: "d342f6ab222c322e5fccf148435ef32bd676d7ce0baa72ea88593ef93bef8ac2", md5CheckSum: "5edb34be3781c079935b9314b4d3340d", contents: .url(catFileURL))

#if os(macOS)
        private static let urlFile = URL(fileURLWithPath: "/tmp/example.url")
#else
        private static let urlFile = URL(fileURLWithPath: "./Resources/example.url")
#endif

    // The specific hash values are obtained from bootstraps in the iOS client test cases.
    static let testUrlFile = TestFile(dropboxCheckSum: "842520e78cc66fad4ea3c5f24ad11734075d97d686ca10b799e726950ad065e7", md5CheckSum: "958c458be74acfcf327619387a8a82c4", contents: .url(urlFile))
}
