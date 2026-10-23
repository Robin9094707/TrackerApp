//
//  GrpcParser.swift
//  Spot
//
//  Created by Leon Böttger on 14.12.24.
//

import Foundation

class GrpcParser {
    static func extractPayload(_ grpc: Data) throws -> Data {
        guard grpc.count >= 5 else {
            throw NSError(domain: "Invalid gRPC response size: \(grpc.count)", code: 1)
        }

        let grpcLenData = grpc.subdata(in: 1 ..< 5)
        let length = try wordToInt(data: grpcLenData)

        guard grpc.count >= 5 + length else {
            throw NSError(domain: "Invalid gRPC payload length: \(grpc.count)", code: 1)
        }

        return grpc.subdata(in: 5 ..< 5 + length)
    }

    static func constructGrpc(_ payload: Data) -> Data {
        // not compressed
        let compressed = Data([0])

        let length = payload.count
        let lengthData = int32ToData(Int32(length))

        return compressed + lengthData + payload
    }
}
