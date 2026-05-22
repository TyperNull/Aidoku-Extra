//
//  Data+Gzip.swift
//  Aidoku
//
//  Gzip compression/decompression support
//

import Foundation
import Compression

extension Data {
    /// Decompresses gzip-compressed data
    func gunzipped() throws -> Data {
        guard count >= 10 else {
            throw GzipError.corruptedData
        }
        
        // Parse gzip header to find start of compressed data
        // Gzip format: https://tools.ietf.org/html/rfc1952
        // Header: ID1(1) ID2(1) CM(1) FLG(1) MTIME(4) XFL(1) OS(1)
        guard self[0] == 0x1f, self[1] == 0x8b else {
            throw GzipError.corruptedData
        }
        
        let flg = self[3]
        var offset = 10 // minimum header size
        
        // FEXTRA
        if flg & 0x04 != 0 {
            guard offset + 2 <= count else { throw GzipError.corruptedData }
            let xlen = Int(self[offset]) | (Int(self[offset + 1]) << 8)
            offset += 2 + xlen
        }
        // FNAME
        if flg & 0x08 != 0 {
            while offset < count && self[offset] != 0 { offset += 1 }
            offset += 1 // skip null terminator
        }
        // FCOMMENT
        if flg & 0x10 != 0 {
            while offset < count && self[offset] != 0 { offset += 1 }
            offset += 1
        }
        // FHCRC
        if flg & 0x02 != 0 {
            offset += 2
        }
        
        guard offset + 8 <= count else {
            throw GzipError.corruptedData
        }
        
        // Strip 8-byte trailer (CRC32 + ISIZE)
        let compressedData = self.subdata(in: offset..<(count - 8))
        
        var decompressed = Data()
        let bufferSize = 65536
        let buffer = UnsafeMutablePointer<UInt8>.allocate(capacity: bufferSize)
        defer {
            buffer.deallocate()
        }
        
        try compressedData.withUnsafeBytes { (inputPointer: UnsafeRawBufferPointer) -> Void in
            guard let baseAddress = inputPointer.baseAddress else {
                throw GzipError.corruptedData
            }
            
            let streamPointer = UnsafeMutablePointer<compression_stream>.allocate(capacity: 1)
            defer {
                streamPointer.deallocate()
            }
            
            var stream = streamPointer.pointee
            var status = compression_stream_init(&stream, COMPRESSION_STREAM_DECODE, COMPRESSION_ZLIB)
            guard status != COMPRESSION_STATUS_ERROR else {
                throw GzipError.initializationFailed
            }
            defer {
                compression_stream_destroy(&stream)
            }
            
            stream.src_ptr = baseAddress.assumingMemoryBound(to: UInt8.self)
            stream.src_size = compressedData.count
            stream.dst_ptr = buffer
            stream.dst_size = bufferSize
            
            repeat {
                status = compression_stream_process(&stream, Int32(COMPRESSION_STREAM_FINALIZE.rawValue))
                
                switch status {
                case COMPRESSION_STATUS_OK:
                    if stream.dst_size == 0 {
                        decompressed.append(buffer, count: bufferSize)
                        stream.dst_ptr = buffer
                        stream.dst_size = bufferSize
                    }
                    
                case COMPRESSION_STATUS_END:
                    decompressed.append(buffer, count: bufferSize - stream.dst_size)
                    
                case COMPRESSION_STATUS_ERROR:
                    throw GzipError.corruptedData
                    
                default:
                    break
                }
            } while status == COMPRESSION_STATUS_OK
        }
        
        return decompressed
    }
    
    enum GzipError: Error {
        case initializationFailed
        case corruptedData
    }
}

