//
//  DateExtras.swift
//  Server
//
//  Created by Christopher Prince on 6/9/17.
//
//

import Foundation

public class DateExtras {
    enum DateFormat : String {
    case DATE
    case DATETIME
    case TIMESTAMP
    case TIME
    }
    
    class func getDateFormatter(format:DateFormat) -> DateFormatter {
        let dateFormatter = DateFormatter()
        dateFormatter.timeZone = TimeZone(abbreviation: "UTC")

        switch format {
        case .DATE:
            dateFormatter.dateFormat = "yyyy-MM-dd"
        
        case .DATETIME, .TIMESTAMP:
            dateFormatter.dateFormat = "yyyy-MM-dd HH:mm:ss"
            
        case .TIME:
            dateFormatter.dateFormat = "HH:mm:ss"
        }
    
        return dateFormatter
    }
    
    class func date(_ date:Date, toFormat format:DateFormat) -> String {
        return getDateFormatter(format: format).string(from: date)
    }
    
    class func date(_ date: String, fromFormat format:DateFormat) -> Date? {
        return getDateFormatter(format: format).date(from: date)
    }
    
    // Compare two dates ignoring sub-second components
    class func equals(_ date1: Date, _ date2:Date) -> Bool {
        let date1String = date(date1, toFormat: .DATETIME)
        let date2String = date(date2, toFormat: .DATETIME)
        return date1String == date2String
    }
}
