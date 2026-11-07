import Vapor
import PostgresBridge

func boot(_ application: Application) throws {
//    _ = SQL.insertInto(Attachment.table, fields: [\Attachment.$id, \Attachment.$objectId, \Attachment.$type, \Attachment.$path, \Attachment.$createdAt, \Attachment.$updatedAt]).values(UUID(), UUID(), AttachmentType.image, "aaa", Date(), Date()).execute(on: try application.db(.psql).psql()).always {
//        switch $0 {
//        case .failure(let error): print("aaa err: \(error)")
//        case .success: print("aaa success")
//        }
//    }
//
//    Attachment(objectId: UUID(), type: .image, path: "aaa").create()
}

//protocol AAA {
//    var wrappedValue: Codable { get }
//}
//
//extension Model {
//    func create() { // swifql db: PostgresDatabase
//        let properties = self.properties
//        let q = SQL
//            .insertInto(Self.table, fields: properties.map { $0.keyPath })
//            .values(properties.map { $0.value })
//            .prepare(.psql).plain
//        print("q: \(q)")
//    }
//}
