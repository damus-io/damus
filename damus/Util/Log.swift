//
//  Log.swift
//  damus
//
//  Created by William Casarin on 2023-08-02.
//

import Foundation
import os.log


enum LogCategory: String {
    case nav
    case render
    case storage
    case networking
    case timeline
    /// Logs related to Nostr Wallet Connect components
    case nwc
    case push_notifications
    case damus_purple
    case image_uploading
    case video_coordination
    case ndb
}

/// Damus structured logger
class Log {
    static private func logger(for logcat: LogCategory) -> OSLog {
        return OSLog(subsystem: "com.jb55.damus", category: logcat.rawValue)
    }

    /// dumb workaround, swift can't forward C vararsg
    static private func log(_ message: StaticString, for log: OSLog, type: OSLogType, _ args: [CVarArg]) {
        switch args.count {
            case 0:
                os_log(message, log: log, type: type)
            case 1:
                os_log(message, log: log, type: type, args[0])
            case 2:
                os_log(message, log: log, type: type, args[0], args[1])
            case 3:
                os_log(message, log: log, type: type, args[0], args[1], args[2])
            case 4:
                os_log(message, log: log, type: type, args[0], args[1], args[2], args[3])
            case 5:
                os_log(message, log: log, type: type, args[0], args[1], args[2], args[3], args[4])
            default:
                os_log("Too many variadic params were sent to the logger so we tossed them!", log: log, type: .error)
                os_log(message, log: log, type: type)
        }
    }

    static func info(_ msg: StaticString, for logcat: LogCategory, _ args: CVarArg...) {
        Log.log(msg, for: logger(for: logcat), type: OSLogType.info, args)
    }
    
    static func debug(_ msg: StaticString, for logcat: LogCategory, _ args: CVarArg...) {
        Log.log(msg, for: logger(for: logcat), type: OSLogType.debug, args)
    }
    
    static func error(_ msg: StaticString, for logcat: LogCategory, _ args: CVarArg...) {
        Log.log(msg, for: logger(for: logcat), type: OSLogType.error, args)
    }
}
