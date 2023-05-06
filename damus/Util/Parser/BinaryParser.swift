//
//  BinaryParser.swift
//  damus
//
//  Created by William Casarin on 2023-04-25.
//

import Foundation

class BinaryParser {
    var pos: Int
    var buf: [UInt8]
    
    init(buf: [UInt8], pos: Int = 0) {
        self.pos = pos
        self.buf = buf
    }
    
    func read_byte() -> UInt8? {
        guard pos < buf.count else {
            return nil
        }
        
        let v = buf[pos]
        pos += 1
        return v
    }
    
    func read_bytes(_ n: Int) -> [UInt8]? {
        guard pos + n < buf.count else {
            return nil
        }
        
        let v = [UInt8](self.buf[pos...pos+n])
        return v
    }
    
    func read_u16() -> UInt16? {
        let start = self.pos

        guard let b1 = read_byte(), let b2 = read_byte() else {
            self.pos = start
            return nil
        }

        return (UInt16(b1) << 8) | UInt16(b2)
    }
}
