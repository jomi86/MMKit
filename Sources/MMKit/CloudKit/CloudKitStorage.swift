import Foundation
import CloudKit

public class CloudKitStorage {
    public init() {}
    
    public func getSavedJSONFileURL(fileName: String) -> URL? {
        if let documentsDirectory = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first {
            return documentsDirectory.appendingPathComponent("\(fileName).json")
        }
        return nil
    }
    
    public func loadRecordsFromJSON<T: Decodable>(fileURL: URL) -> [T]? {
        do {
            let data = try Data(contentsOf: fileURL)
            let decoder = JSONDecoder()
            let records = try decoder.decode([T].self, from: data)
            return records
        } catch {
            print("Error reading or decoding JSON: \(error)")
            return nil
        }
    }
    
    public func convertRecordsToDictionaries(records: [CKRecord]) -> [[String: Any]] {
        var recordDictionaries: [[String: Any]] = []
        
        for record in records {
            var recordDict: [String: Any] = [:]
            
            recordDict["recordID"] = record.recordID.recordName
            
            for key in record.allKeys() {
                recordDict[key] = record.value(forKey: key)
            }
            
            recordDictionaries.append(recordDict)
        }
        
        return recordDictionaries
    }
    
    public func saveToJSONFile(data: [[String: Any]], fileName: String) -> Bool {
        do {
            let jsonData = try JSONSerialization.data(withJSONObject: data, options: .prettyPrinted)
            
            if let documentsDirectory = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first {
                let fileURL = documentsDirectory.appendingPathComponent("\(fileName).json")
                try jsonData.write(to: fileURL)
                return true
            }
        } catch {
            return false
        }
        return false
    }
}
