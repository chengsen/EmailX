import Foundation
import GRDB

final class SQLTrace: @unchecked Sendable {
    private let lock = NSLock()
    private var statements: [String] = []
    func append(_ value: String) { lock.lock(); defer { lock.unlock() }; statements.append(value) }
    func reset() { lock.lock(); defer { lock.unlock() }; statements.removeAll() }
    var text: String { lock.lock(); defer { lock.unlock() }; return statements.joined(separator: "\n") }
}

@main struct DatabaseStartupVerification {
    static func check(_ condition: Bool) { precondition(condition) }

    static func main() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("EmailX-DB-check-\(UUID())")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let trace = SQLTrace()
        var config = Configuration()
        config.prepareDatabase { db in db.trace { trace.append(String(describing: $0)) } }
        let path = directory.appendingPathComponent("db.sqlite").path
        var pool = try DatabasePool(path: path, configuration: config)
        try DatabaseService.createSchema(on: pool)
        precondition(trace.text.contains("rebuild"), "Trace did not observe initial GRDB rebuild")
        try pool.write { db in
            try db.execute(sql: """
                INSERT INTO accounts(id,name,email,imap_host,imap_port,imap_security,smtp_host,smtp_port,smtp_security,auth_type)
                VALUES('a','Test','test@example.com','localhost',993,'ssl','localhost',465,'ssl','password');
                INSERT INTO folders(id,account_id,path,name,display_name) VALUES('f','a','INBOX','INBOX','INBOX');
                INSERT INTO messages(id,uid,subject,from_address,date,folder_id,account_id)
                VALUES('m',1,' legacyneedle ' || char(10),'test@example.com',1,'f','a');
                """)
            // Simulate the existing unrestricted GRDB trigger in a pre-upgrade store.
            try db.execute(sql: """
                DROP TRIGGER __messages_fts_au;
                CREATE TRIGGER __messages_fts_au AFTER UPDATE ON messages BEGIN
                  INSERT INTO messages_fts(messages_fts,rowid,subject,from_name,from_address,to_search,cc_search,bcc_search,list_id,preview,body_text)
                  VALUES('delete',old.rowid,old.subject,old.from_name,old.from_address,old.to_search,old.cc_search,old.bcc_search,old.list_id,old.preview,old.body_text);
                  INSERT INTO messages_fts(rowid,subject,from_name,from_address,to_search,cc_search,bcc_search,list_id,preview,body_text)
                  VALUES(new.rowid,new.subject,new.from_name,new.from_address,new.to_search,new.cc_search,new.bcc_search,new.list_id,new.preview,new.body_text);
                END;
                """)
        }
        trace.reset()
        try pool.write { db in
            try db.execute(sql: "UPDATE messages SET interaction_score=1 WHERE id='m'")
        }
        precondition(trace.text.contains("INSERT INTO messages_fts"), "Trace did not detect legacy FTS update")
        try DatabaseService.runMigrations(on: pool)
        try pool.read { db in
            check(try String.fetchOne(db, sql: "SELECT subject FROM messages WHERE id='m'") == "legacyneedle")
            check(try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM messages_fts WHERE messages_fts MATCH 'legacyneedle'") == 1)
            check(try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM grdb_migrations WHERE identifier IN ('vSelectiveFTSUpdates','vTrimLegacySubjects')") == 2)
        }
        try pool.close()
        pool = try DatabasePool(path: path, configuration: config)
        trace.reset()
        try DatabaseService.createSchema(on: pool)
        try DatabaseService.runMigrations(on: pool)
        precondition(!trace.text.contains("rebuild"), "Second startup rebuilt FTS")
        precondition(!trace.text.contains("SET subject = TRIM"), "Second startup rescanned subjects")
        try pool.read { db in
            check(try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM messages_fts WHERE messages_fts MATCH 'legacyneedle'") == 1)
        }
        print("PASS: reopen preserves index; no rebuild or repeated subject cleanup")

        trace.reset()
        try pool.write { db in
            try db.execute(sql: "UPDATE messages SET interaction_score=5,is_read=1,is_flagged=1,is_answered=1,download_state='complete',size=100 WHERE id='m'")
            try db.execute(sql: "UPDATE messages SET subject=subject,from_name=from_name,from_address=from_address,to_search=to_search,cc_search=cc_search,bcc_search=bcc_search,list_id=list_id,preview=preview,body_text=body_text WHERE id='m'")
        }
        precondition(!trace.text.contains("INSERT INTO messages_fts"), "Non-index/repeated-value update touched FTS")
        try pool.read { db in
            check(try Int.fetchOne(db, sql: "SELECT unread_count FROM folders WHERE id='f'") == 0)
        }
        print("PASS: flags, score, state and identical indexed values do not touch FTS; unread count updates")
        try pool.write { db in
            try db.execute(sql: "UPDATE messages SET body_text='bodyneedle',from_name='Café' WHERE id='m'")
            check(try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM messages_fts WHERE messages_fts MATCH 'bodyneedle AND cafe'") == 1)
            try db.execute(sql: "UPDATE messages SET body_text=NULL,from_name=NULL WHERE id='m'")
            check(try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM messages_fts WHERE messages_fts MATCH 'bodyneedle OR cafe'") == 0)
            let columns = ["subject","from_name","from_address","to_search","cc_search","bcc_search","list_id","preview","body_text"]
            for (i, column) in columns.enumerated() {
                let term = "columnneedle\(i)"
                try db.execute(sql: "UPDATE messages SET \(column)=? WHERE id='m'", arguments: [term])
                check(try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM messages_fts WHERE messages_fts MATCH ?", arguments: [term]) == 1)
            }
            try db.execute(sql: "UPDATE messages SET rowid=100 WHERE id='m'")
            check(try Int.fetchOne(db, sql: "SELECT rowid FROM messages_fts WHERE messages_fts MATCH 'columnneedle0'") == 100)
            try db.execute(sql: "INSERT INTO messages(id,uid,subject,from_address,date,folder_id,account_id) VALUES('m2',2,'insertneedle','test@example.com',2,'f','a')")
            check(try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM messages_fts WHERE messages_fts MATCH 'insertneedle'") == 1)
            try db.execute(sql: "DELETE FROM messages WHERE id IN ('m','m2')")
            check(try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM messages_fts WHERE messages_fts MATCH 'columnneedle0 OR insertneedle'") == 0)
            try db.execute(sql: "INSERT INTO messages_fts(messages_fts,rank) VALUES('integrity-check',1)")
        }
        print("PASS: all indexed fields, NULL transitions, accents, rowid, insert/delete and FTS integrity")
        try pool.close()
    }
}
