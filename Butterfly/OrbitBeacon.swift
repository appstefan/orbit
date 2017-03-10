//
//  OrbitBeacon.swift
//  Orbit
//
//  Created by Stefan Britton on 2016-12-30.
//  Copyright © 2016 Kasama. All rights reserved.
//

import UIKit
import CoreBluetooth

struct OrbitUUID {
    static let beaconServiceUUID = CBUUID(string: "8C422626-0C6E-4B86-8EC7-9147B233D97E")
    static let beaconCharacteristicUUID = CBUUID(string: "A05F9DF4-9D54-4600-9224-983B75B9D154")
}

public enum OrbitBeaconRange: Int {
    case unknown
    case far
    case near
    case immediate
    
    public func stringValue() -> String {
        switch self {
        case .unknown:
            return "Unknown"
        case .far:
            return "Far"
        case .near:
            return "Near"
        case .immediate:
            return "Immediate"
        }
    }
}

protocol OrbitBeaconDelegate {
    func beacon(_ beacon: OrbitBeacon, foundDevices: [String : Any])
    func beacon(_ beacon: OrbitBeacon, bluetoothEnabled: Bool)
}

class OrbitBeacon: NSObject {
    
    var delegate: OrbitBeaconDelegate?
    
    let identifier: String
    var uuidsDetected = [String : [NSNumber]]()
    var peripheralDetected = [String : [NSNumber]]()
    var peripheralUUIDSMatching = [String : String]()
    var peripheralsToBeValidated = [CBPeripheral]()
    
    var isBluetoothEnabled: Bool = false
    
    var peripheralManager: CBPeripheralManager?
    var centralManager: CBCentralManager?
    var characteristic: CBMutableCharacteristic?
    
    var authorizationTimer: Timer?
    var processTimer: Timer?
    var reportTimer: Timer?
    var restartTimer: Timer?

    var isDetecting: Bool = false
    var isBroadcasting: Bool = false

    // MARK: - Initialize
    
    init(identifier: String) {
        self.identifier = identifier
        super.init()
        isBluetoothEnabled = hasBluetooth()
        startAuthorizationTimer()
    }
    
    // MARK: - Actions
    
    func startDetecting() {
        guard centralManager == nil else { return }
        centralManager = CBCentralManager(delegate: self, queue: nil)
    }
    
    func stopDetecting() {
        isDetecting = false
        if let reportTimer = reportTimer {
            reportTimer.invalidate()
            self.reportTimer = nil
        }
        if let centralManager = centralManager {
            centralManager.stopScan()
            self.centralManager = nil
        }
    }
    
    func startScanning() {
        guard let centralManager = centralManager else { return }
        let scanOptions = [CBCentralManagerScanOptionAllowDuplicatesKey : true]
        centralManager.scanForPeripherals(withServices: [OrbitUUID.beaconServiceUUID], options: scanOptions)
        reportTimer = Timer.scheduledTimer(timeInterval: 1.0, target: self, selector: #selector(reportRanges), userInfo: nil, repeats: true)
        processTimer = Timer.scheduledTimer(timeInterval: 2.0, target: self, selector: #selector(processPeripherals), userInfo: nil, repeats: false)
        isDetecting = true
    }
    
    func startBroadcasting() {
        guard canBroadcast() else { return }
        guard peripheralManager == nil else { return }
        peripheralManager = CBPeripheralManager(delegate: self, queue: nil)
    }
    
    func stopBroadcasting() {
        isBroadcasting = false
        if let peripheralManager = peripheralManager {
            peripheralManager.stopAdvertising()
            self.peripheralManager = nil
        }
    }
    
    func startAdvertising() {
        let service = CBMutableService(type: OrbitUUID.beaconServiceUUID, primary: true)
        let dataUUID = identifier.data(using: String.Encoding.utf8)
        characteristic = CBMutableCharacteristic(type: OrbitUUID.beaconCharacteristicUUID, properties: .read, value: dataUUID, permissions: .readable)
        service.characteristics = [characteristic!]
        let advertisingData: [String : Any]  = [CBAdvertisementDataLocalNameKey : "OrbitBeacon", CBAdvertisementDataServiceUUIDsKey : [OrbitUUID.beaconServiceUUID]]
        guard let peripheralManager = peripheralManager else { return }
        peripheralManager.add(service)
        peripheralManager.startAdvertising(advertisingData)
        isBroadcasting = true
    }
    
    func restartScan() {
        for peripheral in peripheralsToBeValidated {
            if peripheral.state == .connecting || peripheral.state == .connected {
                centralManager?.cancelPeripheralConnection(peripheral)
            }
        }
        startScanning()
    }
    
    // MARK: - Report
    
    func reportRanges() {
        for peripheralKey in peripheralUUIDSMatching.keys {
            let ranges = peripheralDetected[peripheralKey]
            let uuid = peripheralUUIDSMatching[peripheralKey]
            uuidsDetected.updateValue(ranges!, forKey: uuid!)
        }
        guard let delegate = delegate else { return }
        let devices = calculateRanges()
        delegate.beacon(self, foundDevices: devices)
        
        for key in peripheralDetected.keys {
            if var lastValues = peripheralDetected[key] {
                lastValues.append(NSNumber(value: -205))
            }
        }
    }
    
    func calculateRanges() -> [String : NSNumber] {
        var ranges = [String : NSNumber]()
        for key in uuidsDetected.keys {
            var proximity: Float = 0.0
            let lastValues = uuidsDetected[key]
            var i: Float = 0.0
            for value in lastValues! {
                if value.floatValue > -25 {
                    var tempVal: Float = 0.0
                    if i > 0 {
                        tempVal = proximity / i
                    }
                    if tempVal > -25 {
                        tempVal = -55
                    }
                    proximity += tempVal
                } else {
                    proximity += value.floatValue
                }
                i += 1
            }
            proximity = proximity / 10.0
            var range: OrbitBeaconRange
            if proximity < -200 {
                range = .unknown
            } else if proximity < -90 {
                range = .far
            } else if proximity < -72 {
                range = .near
            } else if proximity < 0 {
                range = .immediate
            } else {
                range = .unknown
            }
            ranges.updateValue(NSNumber(value: proximity), forKey: key)
        }
        return ranges
    }
    
    func processPeripherals() {
        if peripheralsToBeValidated.count > 0 {
            if let reportTimer = reportTimer {
                reportTimer.invalidate()
                self.reportTimer = nil
            }
            if let centralManager = centralManager {
                centralManager.stopScan()
            }
            for peripheral in peripheralsToBeValidated {
                centralManager?.connect(peripheral, options: nil)
            }
            restartTimer = Timer.scheduledTimer(timeInterval: 3.0, target: self, selector: #selector(restartScan), userInfo: nil, repeats: false)
        } else {
            processTimer = Timer.scheduledTimer(timeInterval: 2.0, target: self, selector: #selector(processPeripherals), userInfo: nil, repeats: false)
        }

    }
    
    // MARK: - Timers
    
    func startAuthorizationTimer() {
        authorizationTimer = Timer.scheduledTimer(timeInterval: 1.0, target: self, selector: #selector(checkBluetoothAuthorization), userInfo: nil, repeats: true)
    }

    // MARK: - Bluetooth
    
    func checkBluetoothAuthorization() {
        if isBluetoothEnabled != hasBluetooth() {
            isBluetoothEnabled = hasBluetooth()
            guard let delegate = delegate else { return }
            delegate.beacon(self, bluetoothEnabled: isBluetoothEnabled)
        }
    }
    
    func hasBluetooth() -> Bool {
        guard let peripheralManager = peripheralManager else { return false }
        return canBroadcast() && peripheralManager.state == .poweredOn
    }
    
    func canBroadcast() -> Bool {
        let status = CBPeripheralManager.authorizationStatus()
        let enabled = status == .authorized || status == .notDetermined
        if !enabled { print("Bluetooth not authorized") }
        return enabled
    }
}

extension OrbitBeacon: CBPeripheralDelegate {
    
    func peripheral(_ peripheral: CBPeripheral, didUpdateValueFor characteristic: CBCharacteristic, error: Error?) {
        guard error == nil else { return }
        guard let data = characteristic.value else { return }
        guard let newString = String(data: data, encoding: String.Encoding.utf8) else { return }
        peripheralUUIDSMatching.updateValue(newString, forKey: peripheral.identifier.uuidString)
        peripheralsToBeValidated.remove(at: peripheralsToBeValidated.index(of: peripheral)!)
        guard let centralManager = centralManager else { return }
        centralManager.cancelPeripheralConnection(peripheral)
    }
    
    func peripheral(_ peripheral: CBPeripheral, didDiscoverCharacteristicsFor service: CBService, error: Error?) {
        if !(error != nil) {
            print("didDiscoverCharacteristics: \(peripheral.identifier.uuidString)")
            peripheral.readValue(for: service.characteristics!.first!)
        } else {
            guard let centralManager = centralManager else { return }
            centralManager.cancelPeripheralConnection(peripheral)
        }
    }
    
    func peripheral(_ peripheral: CBPeripheral, didDiscoverServices error: Error?) {
        if !(error != nil) {
            print("didDiscoverServices: \(peripheral.identifier.uuidString)")
            guard let services = peripheral.services else { return }
            guard let service = services.first else { return }
            peripheral.discoverCharacteristics([OrbitUUID.beaconCharacteristicUUID], for: service)
        } else {
            guard let centralManager = centralManager else { return }
            centralManager.cancelPeripheralConnection(peripheral)
        }
    }
}

extension OrbitBeacon: CBCentralManagerDelegate {
    
    func centralManager(_ central: CBCentralManager, didDiscover peripheral: CBPeripheral, advertisementData: [String : Any], rssi RSSI: NSNumber) {
//        print("didDiscover peripheral: \(peripheral.identifier.uuidString),  data: \(advertisementData), rssi: \(RSSI.floatValue)")
        guard var lastValues = peripheralDetected[peripheral.identifier.uuidString.uppercased()] else {
            peripheralsToBeValidated.append(peripheral)
            peripheralDetected.updateValue([NSNumber](), forKey: peripheral.identifier.uuidString.uppercased())
            return
        }
        for valueRange in lastValues {
            if valueRange.floatValue <= -205 {
                lastValues.remove(at: lastValues.index(of: valueRange)!)
            }
        }
        lastValues.append(RSSI)
        while lastValues.count > 10 {
            lastValues.remove(at: 0)
        }
        peripheralDetected.updateValue(lastValues, forKey: peripheral.identifier.uuidString.uppercased())
    }

    
    public func centralManagerDidUpdateState(_ central: CBCentralManager) {
        print("centralManagerDidUpdateState: \(central.stateString())")
        if central.state == .poweredOn {
            startScanning()
        }
    }
    
    func centralManager(_ central: CBCentralManager, didConnect peripheral: CBPeripheral) {
        print("didConnect peripheral: \(peripheral.identifier.uuidString)")
        peripheral.delegate = self
        peripheral.discoverServices([OrbitUUID.beaconServiceUUID])
    }
    
    
    func centralManager(_ central: CBCentralManager, didFailToConnect peripheral: CBPeripheral, error: Error?) {
        print("didFailToConnect peripheral: \(peripheral.identifier.uuidString)")
    }
}

extension OrbitBeacon: CBPeripheralManagerDelegate {
    
    func peripheralManagerDidUpdateState(_ peripheral: CBPeripheralManager) {
        if peripheral.state == .poweredOn {
            startAdvertising()
        }
    }
    
    func peripheralManagerDidStartAdvertising(_ peripheral: CBPeripheralManager, error: Error?) {
        print("peripheralManagerDidStartAdvertising")
    }
}

extension CBCentralManager {
    func stateString() -> String {
        switch self.state {
        case .poweredOff:
            return "Powered Off"
        case .poweredOn:
            return "Powered On"
        case .resetting:
            return "Resetting"
        case .unauthorized:
            return "Unauthorized"
        case .unknown:
            return "Unknown"
        case .unsupported:
            return "Unsupported"
        }
    }
}






















