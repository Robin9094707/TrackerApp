import XCTest
import CryptoKit
@testable import SpotIntegration

final class GoogleUWBProbeTests: XCTestCase {
    private let nonce = Data([1, 2, 3, 4, 5, 6, 7, 8, 9])
    private let key = Data(repeating: 0x33, count: 16)
    private var payload: Data {
        // OOB v1 response, UWB bit, 20-byte capability TLV. Channels 5+9,
        // preamble 10, config 6, 96 ms, 1 ms slot, initiator.
        Data([1, 1, 1, 0, 0, 20, 0x12, 0x34, 0x20, 0x02, 0, 0, 0, 2, 0, 0, 0x40, 0, 0, 0, 96, 0, 1, 1])
    }
    private func packet(_ payload: Data) -> Data {
        let header = Data([0x0A, UInt8(8 + payload.count)])
        let macData = nonce + header + payload + Data([1])
        let mac = Data(HMAC<CryptoKit.SHA256>.authenticationCode(for: macData, using: SymmetricKey(data: key)).prefix(8))
        return header + mac + payload
    }
    func testAuthenticatedCapabilityRequestAndResponseNeverStartRanging() throws {
        let request = try GoogleUWBProbe.request(authentication: nonce, accountKey: key)
        XCTAssertEqual(request.prefix(2), Data([0x0A, 12]))
        XCTAssertEqual(request.suffix(4), Data([1, 0, 1, 0]))
        let result = try GoogleUWBProbe.response(packet(payload), authentication: nonce, accountKey: key)
        XCTAssertTrue(result.supportsUWB)
        XCTAssertEqual(result.channels, [5, 9])
        XCTAssertEqual(result.configIDs, [6])
        XCTAssertEqual(result.minimumIntervalMS, 96)
        XCTAssertTrue(result.supportsInitiator)
        let absent = try GoogleUWBProbe.response(packet(Data([1, 1, 0, 0])), authentication: nonce, accountKey: key)
        XCTAssertFalse(absent.supportsUWB)
    }
    func testWrongAccountNonceTamperingAndTruncationAreRejected() throws {
        let bytes = packet(payload)
        for count in 0..<bytes.count {
            XCTAssertThrowsError(try GoogleUWBProbe.response(Data(bytes.prefix(count)), authentication: nonce, accountKey: key))
        }
        for index in 0..<bytes.count {
            var altered = bytes; altered[index] ^= 0x80
            XCTAssertThrowsError(try GoogleUWBProbe.response(altered, authentication: nonce, accountKey: key))
        }
        XCTAssertThrowsError(try GoogleUWBProbe.response(bytes, authentication: Data(repeating: 1, count: 9), accountKey: key))
        XCTAssertThrowsError(try GoogleUWBProbe.response(bytes, authentication: nonce, accountKey: Data(repeating: 0, count: 16)))
        XCTAssertThrowsError(try GoogleUWBProbe.request(authentication: Data(), accountKey: key))
    }
    func testAuthenticatedMalformedAndUnsupportedPayloadsDoNotBecomePositiveResults() throws {
        for bad in [Data([2, 1, 1, 0]), Data([1, 1, 1, 0]), Data([1, 1, 1, 0, 0, 0]),
                    Data([1, 1, 1, 0, 0, 20]), Data([1, 1, 0, 0, 0, 2])] {
            XCTAssertThrowsError(try GoogleUWBProbe.response(packet(bad), authentication: nonce, accountKey: key))
        }
    }
}
