from pathlib import Path
import sqlite3
s=Path('MyEmail/Services/SyncService+BackgroundSync.swift').read_text()
start=s.index('WITH counts AS (',s.index('let localUnread:'));end=s.index('""",',start)
sql=s[start:end]
c=sqlite3.connect(':memory:');c.executescript('CREATE TABLE messages(folder_id TEXT,is_read INTEGER);CREATE TABLE folders(id TEXT PRIMARY KEY, unread_count INTEGER,total_count INTEGER); INSERT INTO folders VALUES("f",0,0);')
c.execute(sql,['f','f']); assert c.execute('SELECT changes()').fetchone()[0]==0
c.execute('INSERT INTO messages VALUES("f",0)'); c.execute(sql,['f','f']); assert c.execute('SELECT changes()').fetchone()[0]==1; assert c.execute('SELECT unread_count,total_count FROM folders').fetchone()==(1,1)
c.execute(sql,['f','f']); assert c.execute('SELECT changes()').fetchone()[0]==0
c.execute('UPDATE messages SET is_read=1');c.execute(sql,['f','f']);assert c.execute('SELECT unread_count,total_count FROM folders').fetchone()==(0,1)
c.execute('DELETE FROM messages');c.execute(sql,['f','f']);assert c.execute('SELECT unread_count,total_count FROM folders').fetchone()==(0,0)
print('PASS actual STATUS count SQL: unchanged no writes; arrival/read/deletion counts correct')
