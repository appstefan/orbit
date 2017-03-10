//
//  OrbitCore.swift
//  Orbit
//
//  Created by Stefan Britton on 2016-12-30.
//  Copyright © 2016 Kasama. All rights reserved.
//

import Foundation
import CloudKit

class OrbitCore {
    
    static let main = OrbitCore()
    
    let publicDatabase = CKContainer.default().publicCloudDatabase
    let queue = OperationQueue()
    
    var currentUserRecordID: CKRecordID?
    
    func cloudLogin(completion: @escaping (_ userRecordID: CKRecordID?) -> Void) {
        CKContainer.default().accountStatus { (status, error) in
            guard error == nil else { print(error.debugDescription); return }
            if status == .noAccount {
                completion(nil)
            } else {
                CKContainer.default().fetchUserRecordID(completionHandler: { (recordID, error) in
                    self.currentUserRecordID = recordID
                    completion(recordID)
                })
            }
        }
    }
    
    func deletePlanet(planet: CKRecord, completion: @escaping (_ planetID: CKRecordID?) -> Void) {
        let modifyOperation = CKModifyRecordsOperation(recordsToSave: nil, recordIDsToDelete: [planet.recordID])
        modifyOperation.database = CKContainer.default().publicCloudDatabase
        modifyOperation.modifyRecordsCompletionBlock = { (savedRecords, deletedRecords, error) in
//            print(deletedRecords!)
            DispatchQueue.main.sync(execute: {
                completion(deletedRecords?.first)
            })
        }
        self.queue.addOperation(modifyOperation)
    }
    
    func createPlanet(name: String, completion: @escaping (_ planet: CKRecord?) -> Void) {
        let newPlanet = CKRecord(recordType: "Planet")
        newPlanet.setValue(name, forKey: "name")
        let modifyOperation = CKModifyRecordsOperation(recordsToSave: [newPlanet], recordIDsToDelete: nil)
        modifyOperation.database = CKContainer.default().publicCloudDatabase
        modifyOperation.modifyRecordsCompletionBlock = { (savedRecords, deletedRecords, error) in
//            print(savedRecords!)
            DispatchQueue.main.sync(execute: {
                completion(savedRecords?.first)
            })
        }
        self.queue.addOperation(modifyOperation)
    }
    
    func fetchPlanet(name: String, completion: @escaping (_ planet: CKRecord?) -> Void) {
        var planet: CKRecord?
        let predicate = NSPredicate(format: "name = %@", name)
        let query = CKQuery(recordType: "Planet", predicate: predicate)
        let queryOperation = CKQueryOperation(query: query)
        queryOperation.database = self.publicDatabase
        queryOperation.resultsLimit = 1
        queryOperation.recordFetchedBlock = { (record) in
            planet = record
        }
        queryOperation.queryCompletionBlock = { (cursor, error) in
            DispatchQueue.main.sync(execute: {
                completion(planet)
            })
        }
        self.queue.addOperation(queryOperation)
    }
    
    func fetchDefaultPlanet(completion: @escaping (_ planet: CKRecord?) -> Void) {
        var planet: CKRecord?
        let predicate = NSPredicate(format: "creatorUserRecordID = %@", currentUserRecordID!)
        let query = CKQuery(recordType: "Planet", predicate: predicate)
        let queryOperation = CKQueryOperation(query: query)
        queryOperation.database = self.publicDatabase
        queryOperation.resultsLimit = 1
        queryOperation.recordFetchedBlock = { (record) in
            planet = record
        }
        queryOperation.queryCompletionBlock = { (cursor, error) in
            DispatchQueue.main.sync(execute: {
                completion(planet)
            })
        }
        self.queue.addOperation(queryOperation)
    }
}
