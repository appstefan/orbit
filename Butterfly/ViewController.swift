//
//  ViewController.swift
//  Butterfly
//
//  Created by Stefan Britton on 2017-03-10.
//  Copyright © 2017 Kasama. All rights reserved.
//

import UIKit

class ViewController: UIViewController {

    var beacon = OrbitBeacon(identifier: "Default")
    var devices = [(id: String, range: NSNumber)]()
    @IBOutlet weak var tableView: UITableView!
    
    override func viewDidLoad() {
        super.viewDidLoad()
        beacon.delegate = self
        tableView.dataSource = self
    }
    
    override func viewDidAppear(_ animated: Bool) {
        self.beacon.delegate = self
        self.beacon.startBroadcasting()
        self.beacon.startDetecting()
    }

    override func didReceiveMemoryWarning() {
        super.didReceiveMemoryWarning()
        // Dispose of any resources that can be recreated.
    }


}

extension ViewController: OrbitBeaconDelegate {
    
    func beacon(_ beacon: OrbitBeacon, bluetoothEnabled: Bool) {
        print("bluetoothEnabled: \(bluetoothEnabled)")
    }
    
    func beacon(_ beacon: OrbitBeacon, foundDevices: [String : Any]) {
        print("foundDevices: \(foundDevices)")
        devices = [(id: String, range: NSNumber)]()
        for key in foundDevices.keys {
            let range = foundDevices[key] as! NSNumber
            devices.append((id: key, range: range))
        }
        tableView.reloadData()
    }
    
}

extension ViewController: UITableViewDataSource {
    
    // MARK: UITableViewDataSource
    
    func numberOfSections(in tableView: UITableView) -> Int {
        return 1
    }
    
    func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        return devices.count
    }
    
    func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let cell = tableView.dequeueReusableCell(withIdentifier: "DeviceCell", for: indexPath)
        let device = devices[indexPath.row]
        cell.textLabel!.text = device.id
        cell.detailTextLabel!.text = device.range.stringValue
        return cell
    }
}
