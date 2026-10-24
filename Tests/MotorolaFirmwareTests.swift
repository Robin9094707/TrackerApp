import XCTest
import ZIPFoundation
import SpotIntegration
@testable import RJTracker

final class MotorolaFirmwareTests: XCTestCase {
    private var package: MotorolaFirmwarePackage {
        MotorolaFirmwarePackage(model: .firstGeneration, version: "2.0.104", data: Data(), sha256: "policy-test-only")
    }
    private func info(model: String = "b4122f", firmware: String = "2.0.93", battery: Int = 80) -> MotorolaHardwareInfo {
        .init(modelID: model, firmware: firmware, hardware: "0001", battery: battery)
    }
    func testDowngradesUnknownVersionsOtherModelsAndLowBatteryCannotPassPreflight() throws {
        try MotorolaFirmwarePolicy.validate(info: info(), expectedModelID: "b4122f", package: package)
        try MotorolaFirmwarePolicy.validate(info: info(firmware: "1.0.1", battery: 30), expectedModelID: "b4122f", package: package)
        for blocked in [info(firmware: "2.0.104"), info(firmware: "2.0.105"), info(firmware: "3.0.0"),
                        info(firmware: "0.0.0"), info(firmware: "unknown"), info(firmware: "2.0.93.0"),
                        info(model: "8c9712"), info(model: "3390ea"), info(battery: 29), info(battery: 101)] {
            XCTAssertThrowsError(try MotorolaFirmwarePolicy.validate(info: blocked, expectedModelID: "b4122f", package: package))
        }
    }
    func testVendorReadsValidateTypeLengthResultAndSubfeature() throws {
        XCTAssertEqual(try MotorolaReadProtocol.request(4), Data([0, 4, 128, 0, 0]))
        XCTAssertThrowsError(try MotorolaReadProtocol.request(8)) // no write-name command
        let model = Data([0xB4, 0x12, 0x2F, 1])
        XCTAssertEqual(try MotorolaReadProtocol.model(model), "b4122f")
        XCTAssertEqual(try MotorolaReadProtocol.payload(Data([0, 4, 32, 0, 4]) + model, expected: 4), model)
        for bad in [Data(), Data([0, 4, 0, 0, 4]) + model, Data([0, 4, 33, 0, 4]) + model,
                    Data([0, 5, 32, 0, 4]) + model, Data([0, 4, 32, 0, 5]) + model] {
            XCTAssertThrowsError(try MotorolaReadProtocol.payload(bad, expected: 4))
        }
        let hardware = Data(repeating: 0, count: 19) + Data([2, 0, 93, 0, 1])
        XCTAssertEqual(try MotorolaReadProtocol.hardware(hardware).firmware, "2.0.93")
        XCTAssertThrowsError(try MotorolaReadProtocol.hardware(hardware.dropLast()))
        XCTAssertEqual(try MotorolaReadProtocol.battery(Data([80])), 80)
        XCTAssertThrowsError(try MotorolaReadProtocol.battery(Data([127])))
    }
    func testFakeOriginalFirmwareAndWrongAppArchivesAreRejected() throws {
        XCTAssertThrowsError(try MotorolaFirmwarePackage.validate(Data(repeating: 0, count: MotorolaFirmwarePackage.originalImageSize)))
        XCTAssertThrowsError(try MotorolaFirmwarePackage.decode(Data("not an APK".utf8)))
        let empty = try Archive(accessMode: .create)
        XCTAssertThrowsError(try MotorolaFirmwarePackage.decode(try XCTUnwrap(empty.data)))
        let fake = try Archive(accessMode: .create)
        try fake.addEntry(with: MotorolaFirmwarePackage.assetPath, type: .file, uncompressedSize: Int64(4)) { _, _ in Data([1, 2, 3, 4]) }
        XCTAssertThrowsError(try MotorolaFirmwarePackage.decode(try XCTUnwrap(fake.data)))
    }
}
