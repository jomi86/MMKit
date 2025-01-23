import CloudKit

public final class CloudKitImporter {
    let developmentDatabase: CKDatabase
    let productionDatabase: CKDatabase
    
    init(developmentIdentifier: String, productionIdentifier: String) {
        let developmentContainer = CKContainer(identifier: developmentIdentifier)
        let productionContainer = CKContainer(identifier: productionIdentifier)

        developmentDatabase = developmentContainer.publicCloudDatabase
        productionDatabase = productionContainer.publicCloudDatabase
    }
    
    func migrateDataToProduction(recordType: String) {
        // Query records in development
        let query = CKQuery(recordType: recordType, predicate: NSPredicate(value: true))
        developmentDatabase.perform(query, inZoneWith: nil) { records, error in
            if let error = error {
                print("MMKit - CloudKitImporter - Error fetching records from development: \(error)")
                return
            }

            guard let records = records else { return }
            
            print("MMKit - CloudKitImporter - migrateDataToProduction records count: \(records.count)")

            // Save records to production
            for record in records {
                print("MMKit - CloudKitImporter - migrateDataToProduction record: \(record)")
                let newRecord = CKRecord(recordType: record.recordType)
                newRecord.setValuesForKeys(record.dictionaryWithValues(forKeys: record.allKeys()))
                self.productionDatabase.save(newRecord) { _, error in
                    if let error = error {
                        print("MMKit - CloudKitImporter - Error saving record to production: \(error)")
                    }
                }
            }
        }
    }
}

