# Compile production reading view layouts against isolated data/service stubs.
# No database, network, attachment IO or HTML rendering is exercised here.
# Source UI is read at execution time; temporary copies only remove external
# model-module imports or expose the private EML header for size measurement.
from pathlib import Path
import tempfile, subprocess
stubs='''import AppKit
import SwiftUI
import Observation
struct Message { var fromAddress="sender@example.test"; var fromName: String?="Sender"; var toAddresses=["recipient@example.test"]; var ccAddresses:[String]=[]; var replyToAddresses:[String]=[]; var subject="Subject"; var date=Date(); var userAgent:String? }
struct EmailMessage {var subject:String?="Subject";var from=[EmailAddress("sender@example.test")!];var to=[EmailAddress("recipient@example.test")!];var cc:[EmailAddress]=[];var date:Date?=Date()}
struct EmailAddress { var name:String?; var address:String; init?(_ raw:String) { address=raw; name=nil }; static func emailOnly(from raw:String)->String { raw }; static func displayName(from raw:String)->String {raw} }
@Observable final class AppState {var searchText=""}
final class TrustedSenderService {func addTrusted(_ email:String){}}
@Observable final class AppEnvironment {let trustedSenderService=TrustedSenderService()}
enum ComposeMode {case newMessage}
final class AppDelegate:NSObject,NSApplicationDelegate {func openCompose(mode:ComposeMode){}}
final class MUAResolverClient {struct Resolved {let pngData:Data?;let displayName:String}; static let shared=MUAResolverClient(); func resolve(userAgent:String) async->Resolved? {nil}}
struct Attachment:Identifiable {let id=UUID();var filename:String;var mimeType="application/octet-stream";var size:Int64=100;var localPath:String?}
enum FormatHelpers {static func formatByteCount(_ n:Int64)->String {ByteCountFormatter.string(fromByteCount:n,countStyle:.file)}}
final class QuickLookCoordinator {func show(urls:[URL],selectedIndex:Int){}}
final class EmlViewerService {static let shared=EmlViewerService();func open(url:URL){}}
enum LogLevel {case error};enum LogCategory {case sync}
enum LogService {static func log(_ l:LogLevel,_ c:LogCategory,_ message:String,detail:String){}}
'''
probe='''import SwiftUI
import AppKit
@main struct Probe {
@MainActor static func main() {
_ = NSApplication.shared
func measure<V:View>(_ v:V, width:CGFloat)->CGSize {
 let host=NSHostingView(rootView:v.frame(width:width).fixedSize(horizontal:false,vertical:true));return host.fittingSize
}
let env=AppEnvironment(); let state=AppState()
for width:CGFloat in [280,500] {
var longMessage=Message();longMessage.subject=String(repeating:"Long multiline subject 主题\\n",count:100)
longMessage.toAddresses=(1...100).map {"Recipient \\($0) " + String(repeating:"address",count:12)+"@example.test"}
let uncapped=measure(MessageHeaderBar(message:longMessage,maximumHeight:10000).environment(env).environment(state),width:width)
var longEml=EmailMessage();longEml.subject=longMessage.subject
longEml.to=longMessage.toAddresses.compactMap(EmailAddress.init)
let eml=measure(EmlViewerHeader(email:longEml,dateFormatter:DateFormatter(),maximumHeight:134),width:width)
let uncappedEml=measure(EmlViewerHeader(email:longEml,dateFormatter:DateFormatter(),maximumHeight:10000),width:width)
let short=measure(MessageHeaderBar(message:Message(),maximumHeight:134).environment(env).environment(state),width:width)
let long=measure(MessageHeaderBar(message:longMessage,maximumHeight:134).environment(env).environment(state),width:width)
let one=measure(AttachmentStripView(attachments:[Attachment(filename:"short.txt")],onRefetch:{_ in nil},maximumHeight:84),width:width)
let many=measure(AttachmentStripView(attachments:(1...100).map {Attachment(filename:"File \\($0) " + String(repeating:"long name 附件",count:12)+".txt")},onRefetch:{_ in nil},maximumHeight:84),width:width)
print("VIEWPORT width",width,"header short/long",short,long,"full header",uncapped,"EML bounded/full",eml,uncappedEml,"attachments one/many",one,many)
precondition(long.width<=width+1 && long.height<=135)
precondition(uncapped.height>134 && uncappedEml.height>134)
precondition(eml.width<=width+1 && eml.height<=135)
precondition(many.width<=width+1 && many.height<=85)
precondition(one.height<many.height)
}
}
}
'''
with tempfile.TemporaryDirectory(prefix='emailx-reading-layout-') as d:
 p=Path(d);(p/'stubs.swift').write_text(stubs);(p/'probe.swift').write_text(probe)
 header=Path('MyEmail/Views/MessageHeaderBar.swift').read_text().replace('import SwiftMail\n','').replace('SwiftMail.EmailAddress','EmailAddress')
 (p/'MessageHeaderBar.swift').write_text(header)
 eml_header=Path('MyEmail/Views/EmlViewerView.swift').read_text().split('// MARK: - Header subview',1)[1].replace('private struct EmlViewerHeader','struct EmlViewerHeader',1)
 (p/'EmlViewerHeader.swift').write_text('import SwiftUI\n'+eml_header)
 subprocess.run(['xcrun','swiftc','-parse-as-library',str(p/'stubs.swift'),str(p/'MessageHeaderBar.swift'),str(p/'EmlViewerHeader.swift'),'MyEmail/Views/InitialsAvatarView.swift','MyEmail/Utilities/FlowLayout.swift','MyEmail/Views/AttachmentStripView.swift',str(p/'probe.swift'),'-o',str(p/'probe')],check=True)
 subprocess.run([str(p/'probe')],check=True)
