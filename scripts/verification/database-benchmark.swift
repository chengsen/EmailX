import Foundation
import GRDB

@main struct DatabaseBenchmark {
    static func timed(_ operation: () throws -> Void) rethrows -> Double {
        let start = DispatchTime.now().uptimeNanoseconds
        try operation()
        return Double(DispatchTime.now().uptimeNanoseconds - start) / 1_000_000
    }

    static func main() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("EmailX-DB-benchmark-\(UUID())")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let body = (0..<300).map { "token\($0)" }.joined(separator: " ")
        var results: [[String: Any]] = []
        for count in [1_000, 10_000] {
            let pool = try DatabasePool(path: directory.appendingPathComponent("\(count).sqlite").path)
            try DatabaseService.createSchema(on: pool)
            try DatabaseService.runMigrations(on: pool)
            try pool.write { db in
                try db.execute(sql: """
                    INSERT INTO accounts(id,name,email,imap_host,imap_port,imap_security,smtp_host,smtp_port,smtp_security,auth_type)
                    VALUES('a','Test','sender@example.invalid','localhost',993,'ssl','localhost',465,'ssl','password');
                    INSERT INTO folders(id,account_id,path,name,display_name) VALUES('f','a','INBOX','INBOX','INBOX');
                    """)
                let insert = try db.makeStatement(sql: """
                    INSERT INTO messages(id,uid,subject,from_name,from_address,to_search,preview,body_text,date,folder_id,account_id)
                    VALUES(?,?,?,'Sender','sender@example.invalid','recipient@example.invalid','Preview',?,?,'f','a')
                    """)
                for index in 0..<count {
                    try insert.execute(arguments: ["m\(index)", index + 1, "Subject \(index)", body, index])
                }
            }
            // Fixture creation and initial migrations are excluded. Both variants
            // repeat the application's existing-store startup sequence on a warm pool.
            var startup: [Double] = []
            for _ in 0..<3 {
                startup.append(try timed {
                    try DatabaseService.createSchema(on: pool)
                    try DatabaseService.runMigrations(on: pool)
                })
            }
            var scoreUpdates: [Double] = []
            for _ in 0..<3 {
                scoreUpdates.append(try timed {
                    try pool.write { db in
                        try db.execute(sql: "UPDATE messages SET interaction_score=interaction_score+1 WHERE rowid<=1000")
                    }
                })
            }
            try pool.write { db in
                try db.execute(sql: "INSERT INTO messages_fts(messages_fts,rank) VALUES('integrity-check',1)")
            }
            results.append([
                "rows": count,
                "body_utf8_bytes_per_row": body.utf8.count,
                "startup_existing_store_ms_runs": startup,
                "startup_existing_store_ms_median": startup.sorted()[1],
                "score_update_1000_rows_ms_runs": scoreUpdates,
                "score_update_1000_rows_ms_median": scoreUpdates.sorted()[1]
            ])
            try pool.close()
        }
        let json = try JSONSerialization.data(withJSONObject: results, options: [.prettyPrinted, .sortedKeys])
        print(String(decoding: json, as: UTF8.self))
    }
}
