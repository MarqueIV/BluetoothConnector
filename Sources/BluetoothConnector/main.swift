import IOBluetooth
import ArgumentParser

protocol BluetoothAddressedDevice: AnyObject {
    var bluetoothAddress: String? { get }
}

extension IOBluetoothDevice: BluetoothAddressedDevice {
    var bluetoothAddress: String? { addressString }
}

func normalizedMacAddress(_ address: String) -> String {
    address.lowercased()
}

func resolveBluetoothDevice<Device: BluetoothAddressedDevice>(
    macAddress: String,
    pairedDevices: [Device],
    deviceFactory: (String) -> Device?
) -> Device? {
    let normalizedAddress = normalizedMacAddress(macAddress)

    if let pairedDevice = pairedDevices.first(where: {
        guard let address = $0.bluetoothAddress else { return false }
        return normalizedMacAddress(address) == normalizedAddress
    }) {
        return pairedDevice
    }

    return deviceFactory(normalizedAddress)
}

func utilityName() -> String {
  return URL(fileURLWithPath: CommandLine.arguments.first ?? "¯\\_(ツ)_/¯").lastPathComponent
}

func getDeviceListHelpString() -> String {
    let header = "\nMAC Address missing. Get the MAC address from the list below (if your device is missing, pair it with your computer first):"
    let columnTitles = "MAC Address         Status      RSSI   Device Name"
    var helpLines = [header, columnTitles]
    
    IOBluetoothDevice.pairedDevices().forEach { device in
        guard let device = device as? IOBluetoothDevice,
              let addressString = device.addressString,
              let deviceName = device.name
        else { return }
        
        let connected = device.isConnected()
        let connectedString = connected ? "Connected" : "         "
        let rssiString = connected ? String(format: "%4d", Int(device.rawRSSI())) : "    "
        
        helpLines.append([addressString, connectedString, rssiString, deviceName].joined(separator: "   "))
    }
    
    return helpLines.joined(separator: "\n")
}

func printAndNotify(title: String, body: String, notify: Bool) {
    if (notify) {
        Process.launchedProcess(launchPath: "/usr/bin/osascript", arguments: ["-e", "display notification \"\(body)\" with title \"\(title)\""])
    }

    print(body)
}

func turnOnBluetoothIfNeeded(notify: Bool) {
    guard let bluetoothHost = IOBluetoothHostController.default(),
    bluetoothHost.powerState != kBluetoothHCIPowerStateON else { return }

    // Definitely not App Store safe
    if let iobluetoothClass = NSClassFromString("IOBluetoothPreferences") as? NSObject.Type {
        let obj = iobluetoothClass.init()
        let selector = NSSelectorFromString("setPoweredOn:")
        if (obj.responds(to: selector)) {
            obj.perform(selector, with: 1)
        }
    }

    var timeWaited : UInt32 = 0
    let interval : UInt32 = 200000 // in microseconds
    while (bluetoothHost.powerState != kBluetoothHCIPowerStateON) {
        usleep(interval)
        timeWaited += interval
        if (timeWaited > 5000000) {
            printAndNotify(title: utilityName(), body: "Failed to turn on Bluetooth", notify: notify)
            exit(-2)
        }
    }
}

enum ActionType {
    case Connection
    case Disconnect
}

func actionSucceeded(action: ActionType, error: IOReturn, isConnected: Bool) -> Bool {
    guard error == kIOReturnSuccess else { return false }

    switch action {
        case .Connection:
            return isConnected
        case .Disconnect:
            return !isConnected
    }
}

func execute(macAddress: String, connectOnly: Bool, disconnectOnly: Bool, notify: Bool, statusOnly: Bool) {
    let pairedDevices = IOBluetoothDevice.pairedDevices().compactMap { $0 as? IOBluetoothDevice }
    guard let bluetoothDevice = resolveBluetoothDevice(
        macAddress: macAddress,
        pairedDevices: pairedDevices,
        deviceFactory: { IOBluetoothDevice(addressString: $0) }
    ) else {
        printAndNotify(title: utilityName(), body: "Device not found", notify: notify)
        exit(-2)
    }

    if !bluetoothDevice.isPaired() {
        printAndNotify(title: utilityName(), body: "Not paired to device", notify: notify)
        exit(-4)
    }

    let alreadyConnected = bluetoothDevice.isConnected()
    let shouldConnect = (connectOnly
                        || (!connectOnly && !disconnectOnly && !alreadyConnected))

    if statusOnly {
        if alreadyConnected {
            print("Connected")
        }
        else {
            print("Disconnected")
        }
        exit(0)
    }

    var error : IOReturn = kIOReturnSuccess
    var action : ActionType
    if shouldConnect {
        action = .Connection
        if !alreadyConnected {
            turnOnBluetoothIfNeeded(notify: notify)
            error = bluetoothDevice.openConnection()
        }
    }
    else {
        action = .Disconnect

        // call closeConnection up to 10 times with a 500ms delay between each call until the connection is closed
        var attempts = 0
        while (attempts < 10 && bluetoothDevice.isConnected()) {
            error = bluetoothDevice.closeConnection()
            usleep(500000)
            attempts += 1
        }
    }

    let title = bluetoothDevice.name ?? utilityName()
    if !actionSucceeded(action: action, error: error, isConnected: bluetoothDevice.isConnected()) {
        printAndNotify(title: title, body: "\(action) failed", notify: notify)
        exit(-1)
    } else if notify {
        if action == .Connection && alreadyConnected {
            printAndNotify(title: title, body: "Already connected", notify: notify)
        }
        else if action == .Disconnect && !alreadyConnected {
            printAndNotify(title: title, body: "Already disconnected", notify: notify)
        }
        else {
            switch action {
                case .Connection:
                    printAndNotify(title: title, body: "Connected", notify: notify)

                case .Disconnect:
                    printAndNotify(title: title, body: "Disconnected", notify: notify)
            }
        }
    }
}

struct BluetoothConnector: ParsableCommand {
    @Flag(name: .shortAndLong, help: "Connect a device")
    var connect = false

    @Flag(name: .shortAndLong, help: "Disconnect a device")
    var disconnect = false

    @Flag(name: .shortAndLong, help: "Get the status of a device")
    var status = false

    @Flag(name: .shortAndLong, help: "Post a Notification Center notification")
    var notify = false

    @Argument(help: ArgumentHelp(
        "The MAC address of the device. Format: 00-00-00-00-00-00 or 000000000000",
        valueName: "MAC address"))
    var macAddress: String?

    static var configuration = CommandConfiguration(
        commandName: utilityName(),
        abstract: "Connect/disconnects Bluetooth devices.",
        discussion: "Default behavior is to toggle between connecting and disconnecting.")

    mutating func validate() throws {
        guard connect != true || disconnect != true else {
            throw ValidationError("Can't connect and disconnect at once.")
        }

        if status {
            guard connect == false else {
                throw ValidationError("Can't connect with status flag enabled.")
            }

            guard disconnect == false else {
                throw ValidationError("Can't disconnect with status flag enabled.")
            }
        }

        if let address = macAddress {
            if address.replacingOccurrences(of: "-", with: "").count != 12 {
                throw ValidationError("Invalid MAC address: \(address).")
            }
        }
        else {
            throw ValidationError(getDeviceListHelpString())
        }
    }

    func run() throws {
        execute(macAddress: macAddress!, connectOnly: connect, disconnectOnly: disconnect, notify: notify, statusOnly: status)
    }
}

BluetoothConnector.main()
