import CloudKit

@available(iOS 15.0, *)
public final class CloudKitImporter {
    let database: CKDatabase
    
    public init(developmentIdentifier: String) {
        let container = CKContainer(identifier: developmentIdentifier)
        database = container.publicCloudDatabase
    }
    
    public func saveDevelopmentDatabase(type: String) async {
        // Query records in development
        let query = CKQuery(recordType: type, predicate: NSPredicate(value: true))
        let qop = CKQueryOperation(query: query)
        
        database.add(qop)
        
        var allRecords: [CKRecord] = []
        do {
            var result = try await database.records(matching: query)
            for resultItem in result.matchResults.enumerated() {
                let record = try resultItem.element.1.get()
                allRecords.append(record)
            }
            if let cursor = result.queryCursor.take() {
                let records = try await database.records(continuingMatchFrom: cursor)
                for resultItemAgain in records.matchResults.enumerated() {
                    let record1 = try resultItemAgain.element.1.get()
                    allRecords.append(record1)
                }
            }
        } catch {
            print("MMKit - CloudKitImporter - Error fetching records from development: \(error)")
        }
        }
//        queryCompletionBlock = { (c:CKQueryCursor!, e:NSError!) -> Void in
//          if nil != c {
//            // there is more to do; create another op
//            var newQop = CKQueryOperation (cursor: c!)
//            newQop.resultsLimit = qop.resultsLimit
//            newQop.queryCompletionBlock = qop.queryCompletionBlock
//
//            // Hang on to it, if we must
//            qop = newQop
//
//            // submit
//            ....addOperation(qop)
//          }
//        }
//
//        ....addOperation(qop)
//        database.perform(query, inZoneWith: nil) { records, error in
//            if let error = error {
//                print("MMKit - CloudKitImporter - Error fetching records from development: \(error)")
//                return
//            }
//            
//            guard let records = records else { return }
//            
//            let urls = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)
//            let docsDirectoryURL = urls[0]
//            let ckStyleURL = docsDirectoryURL.appendingPathComponent("\(type)_ckstylerecords.data")
//            
//            do {
//                let data : Data = try NSKeyedArchiver.archivedData(withRootObject: records, requiringSecureCoding: true)
//                
//                try data.write(to: ckStyleURL, options: .atomic)
//                print("MMKit - CloudKitImporter - data write ckStyleRecords successful")
//                
//            } catch {
//                print("MMKit - CloudKitImporter - could not save ckStyleRecords to documents directory")
//            }
//        }
//    }
    
    public func importDatabaseFromFile(type: String, completion: @escaping ([CKRecord]) -> Void) {
        let urls = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)
        let docsDirectoryURL = urls[0]
        let ckStyleURL = docsDirectoryURL.appendingPathComponent("\(type)_ckstylerecords.data")
        
        var newRecords : [CKRecord] = []
        if FileManager.default.fileExists(atPath: ckStyleURL.path) {
            do {
                let data = try Data(contentsOf:ckStyleURL)
                
                //yes, I know this has been deprecated, but I can't seem to get the new format to work
                if let theRecords: [CKRecord] = try NSKeyedUnarchiver.unarchiveObject(with: data) as? [CKRecord] {
                    newRecords = theRecords
                    print("MMKit - CloudKitImporter - newRecords.count is \(newRecords.count)")
                }
                
            } catch {
                print("MMKit - CloudKitImporter - could not retrieve ckStyleRecords from documents directory")
            }
            
        }
        completion(newRecords)
    }
}

