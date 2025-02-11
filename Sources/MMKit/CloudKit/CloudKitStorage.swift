import Foundation
import CloudKit

public enum CloudKitStorageError: Error {
    case jsonEncoder
    case prepareStorage
    case dataWrite
    
    public var description: String {
        switch self {
        case .jsonEncoder:
            "Error encoding records array to JSON"
        case .prepareStorage:
            "Error preparing device storage"
        case .dataWrite:
            "Error writing data to device storage"
        }
    }
}

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
    
    @MainActor
    public func saveRecordsToData<T: Codable>(records: [T]) throws -> Data {
        do {
            let encoder = JSONEncoder()
            let data = try encoder.encode(records)
            return data
        } catch {
            throw CloudKitStorageError.jsonEncoder
        }
    }
    
    public func saveDataToFile(data: Data, fileName: String) throws {
        do {
            guard let documentsDirectory = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first else {
                throw CloudKitStorageError.prepareStorage
            }
            let fileURL = documentsDirectory.appendingPathComponent("\(fileName).json")
            try data.write(to: fileURL)
        } catch {
            throw CloudKitStorageError.dataWrite
        }
    }
}
