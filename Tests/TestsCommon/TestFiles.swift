//
//  TestFiles.swift
//  ServerTests
//
//  Created by Christopher G Prince on 10/23/18.
//

import Foundation
@testable import Server
import XCTest
import ServerShared

struct TestFile {
    enum FileContents {
        case string(String)
        case url(URL)
        
        func equal(to data: Data) -> Bool {
            switch self {
            case .string(let string):
                guard let dataString = String(data: data, encoding: .utf8) else {
                    return false
                }
                return dataString == string
                
            case .url(let url):
                guard let urlData = try? Data(contentsOf: url) else {
                    return false
                }
                
                return data == urlData
            }
        }
    }
    
    let dropboxCheckSum:String?
    let md5CheckSum:String? // Google
    let sha1Hash: String? // Microsoft
    
    let contents: FileContents
    let mimeType: MimeType
    
    func checkSum(type: AccountScheme.AccountName) -> String! {
        switch type {
        case AccountScheme.google.accountName:
            return md5CheckSum
        case AccountScheme.dropbox.accountName:
            return dropboxCheckSum
        case AccountScheme.facebook.accountName:
            return nil
        case AccountScheme.microsoft.accountName:
            return sha1Hash
            
        default:
            XCTFail()
            return nil
        }
    }
    
    // The specific md5 and dropbox hash values are obtained from bootstraps in the iOS client test cases.
    // SHA1 hashes generated online-- https://passwordsgenerator.net/sha1-hash-generator/
    
    static let commentFile = TestFile(
        dropboxCheckSum: "3ffce28e9fc6181b1e52226cba61dbdbd13fc1b75decb770f075541b25010575",
        md5CheckSum: "d1139c432dadc28a5fb06c4c68d51790",
        sha1Hash: "BDCCBF12CDFB5CAA9EB56B86F90BAD4141913DE9",
        contents: .string("{\"elements\":[]}"),
        mimeType: .text)
        
    static let test1 = TestFile(
        dropboxCheckSum: "42a873ac3abd02122d27e80486c6fa1ef78694e8505fcec9cbcc8a7728ba8949",
        md5CheckSum: "b10a8db164e0754105b7a99be72e3fe5",
        sha1Hash: "0A4D55A8D778E5022FAB701977C5D840BBC486D0",
        contents: .string("Hello World"),
        mimeType: .text)
    
    static let test2 = TestFile(
        dropboxCheckSum: "3e1c5665be7f2f5552efb9fd93df8fe9d58c54619fefe1a5b474e38464391011",
        md5CheckSum: "a9d2b23e3001e558213c4ee056f31ba1",
        sha1Hash: "3480185FC5811EC5F242E13B23E2D9274B080EF1",
        contents: .string("This is some longer text that I'm typing here and hopefullly I don't get too bored"),
        mimeType: .text)

#if os(macOS)
        private static let catFileURL = URL(fileURLWithPath: "/tmp/Cat.jpg")
#else
        private static let catFileURL = URL(fileURLWithPath: "./Resources/Cat.jpg")
#endif

    static let catJpg = TestFile(
        dropboxCheckSum: "d342f6ab222c322e5fccf148435ef32bd676d7ce0baa72ea88593ef93bef8ac2",
        md5CheckSum: "5edb34be3781c079935b9314b4d3340d",
        sha1Hash: "41CA4AF2CE9C85D4F9969EA5D5C551D1FABD4857",
        contents: .url(catFileURL),
        mimeType: .jpeg)
        
#if os(macOS)
        // DEPRECATED-- not working
        private static let catMovURL = URL(fileURLWithPath: "/tmp/Cat.mov")
#else
        private static let catMovURL = URL(fileURLWithPath: "./Resources/Cat.mov")
#endif

    static let catMov = TestFile(
        dropboxCheckSum: "8de78010c152c2d44ae50e05ecfacc48976c6bc155ab532a895ac1abfc1c542d",
        md5CheckSum: "c5bf2451067cfdc94e674312c7807fb8",
        sha1Hash: "BF0DDB033035AE4EBB8267BF4D920183E9BC4B95",
        contents: .url(catMovURL),
        mimeType: .mov)
        
#if os(macOS)
        // DEPRECATED-- not working
        private static let catPngURL = URL(fileURLWithPath: "/tmp/Cat.png")
#else
        private static let catPngURL = URL(fileURLWithPath: "./Resources/Cat.png")
#endif

    static let catPng = TestFile(
        dropboxCheckSum: "d8037620a8c3a506ec3b5b94353df15f24331c133eb7690434b11fa36205b209",
        md5CheckSum: "b1dc755767401bd59352fa0a4a78d17b",
        sha1Hash: "6C464286C12E8232382F829793249F55354FDB16",
        contents: .url(catPngURL),
        mimeType: .png)

#if os(macOS)
        private static let urlFile = URL(fileURLWithPath: "/tmp/example.url")
#else
        private static let urlFile = URL(fileURLWithPath: "./Resources/example.url")
#endif

    static let testUrlFile = TestFile(
        dropboxCheckSum: "842520e78cc66fad4ea3c5f24ad11734075d97d686ca10b799e726950ad065e7",
        md5CheckSum: "958c458be74acfcf327619387a8a82c4",
        sha1Hash: "92D74581DBCBC143ED68079A476CD770BE7E4BD9",
        contents: .url(urlFile),
        mimeType: .url)
        
    static let testNoCheckSum = TestFile(
        dropboxCheckSum: nil,
        md5CheckSum: nil,
        sha1Hash: nil,
        contents: .string("Hello World"),
        mimeType: .text)
        
    static let testBadCheckSum = TestFile(
        dropboxCheckSum: "blah",
        md5CheckSum: "blah",
        sha1Hash: "blah",
        contents: .string("Hello World"),
        mimeType: .text)
}
