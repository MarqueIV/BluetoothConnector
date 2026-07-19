import XCTest
@testable import BluetoothConnector

final class BluetoothConnectorTests: XCTestCase {
    private final class Device: BluetoothAddressedDevice {
        let bluetoothAddress: String?

        init(address: String) {
            bluetoothAddress = address
        }
    }

    func testMacAddressesAreNormalizedToLowercase() {
        XCTAssertEqual(normalizedMacAddress("20-F4-D4-4D-D4-ED"), "20-f4-d4-4d-d4-ed")
    }

    func testDeviceLookupReturnsTheDeviceFromThePairedList() {
        let pairedDevice = Device(address: "da-84-3e-56-b9-bf")
        let reconstructedDevice = Device(address: "da-84-3e-56-b9-bf")

        let result = resolveBluetoothDevice(
            macAddress: "DA-84-3E-56-B9-BF",
            pairedDevices: [pairedDevice],
            deviceFactory: { _ in reconstructedDevice }
        )

        XCTAssertTrue(result === pairedDevice)
    }

    func testSuccessfulReturnCodeDoesNotReportAConnectionWhenDeviceIsDisconnected() {
        XCTAssertFalse(actionSucceeded(action: .Connection, error: kIOReturnSuccess, isConnected: false))
    }

    func testNegativeErrorCodeDoesNotReportSuccess() {
        XCTAssertFalse(actionSucceeded(action: .Connection, error: kIOReturnError, isConnected: true))
    }
}
