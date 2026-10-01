# Compile production reading view layouts against isolated data/service stubs.
# No database, network, attachment IO or HTML rendering is exercised here.
# Source UI is read at execution time; temporary copies only remove external
# model-module imports or expose the private EML header for size measurement.
# Complete reading windows use a native document rectangle stub to check the
# allocated body viewport; this does not validate WebKit or real keyboard/AX UI.
from pathlib import Path
import tempfile, subprocess
stubs='''import AppKit
import SwiftUI
import Observation
struct Message {var id=UUID();var accountID=UUID();var bodyHTML:String?="<p>Body</p>";var bodyText:String?="Body";var isEncrypted=false;var isRead=true;var fromAddress="sender@example.test"; var fromName: String?="Sender"; var toAddresses=["recipient@example.test"]; var ccAddresses:[String]=[]; var replyToAddresses:[String]=[]; var subject="Subject"; var date=Date(); var userAgent:String? }
struct EmailMessage {var subject:String?="Subject";var from=[EmailAddress("sender@example.test")!];var to=[EmailAddress("recipient@example.test")!];var cc:[EmailAddress]=[];var date:Date?=Date();var htmlBody:String?="<p>Body</p>";var textBody:String?="Body"}
struct EmailAddress { var name:String?; var address:String; init?(_ raw:String) { address=raw; name=nil }; static func emailOnly(from raw:String)->String { raw }; static func displayName(from raw:String)->String {raw} }
@Observable final class AppState {var searchText=""}
final class TrustedSenderService {func addTrusted(_ email:String){};func isTrusted(_ email:String)->Bool {false}}
@MainActor @Observable final class AppEnvironment {let trustedSenderService=TrustedSenderService();let syncService=FixtureSyncService();let undoService=FixtureUndoService();let gravatarService=FixtureGravatarService()}
@MainActor final class FixtureSyncService {
var message:Message?;var attachments:[Attachment]=[]
func loadFullMessage(id:UUID) async throws->Message? {message}
func loadAttachments(for id:UUID) async throws->(inlineRefs:[InlineRef],regular:[Attachment]) {([],attachments)}
func refetchAttachment(_ a:Attachment) async throws->Attachment {a}
func markAsRead(_ ids:[UUID]) async {};func markAsJunk(_ ids:[UUID]) async {}
func fetchRawSource(messageID:UUID) async throws->String {"Fixture raw source"}
}
@MainActor final class FixtureUndoService {func archiveMessages(_ ids:[UUID],undoManager:UndoManager?) async {};func deleteMessages(_ ids:[UUID],undoManager:UndoManager?) async {}}
final class FixtureGravatarService {func avatar(for email:String)->NSImage? {nil}}
struct InlineRef:Sendable {}
extension Notification.Name {static let messageDidResync=Notification.Name("FixtureMessageDidResync")}
enum HTMLHeadInjector {static func prepare(html:String,allowRemoteContent:Bool,inlineAttachments:[InlineRef])->String {html};static func wrapPlainText(_ text:String,fontSize:Int,monospace:Bool,quoteColor1:String,quoteColor2:String,quoteColor3:String)->String {text}}
final class BodyProbeNSView:NSView {override var acceptsFirstResponder:Bool {true}}
struct HTMLMailView:NSViewRepresentable {
let html:String;let baseURL:URL?;var inlineRefs:[InlineRef]=[]
func makeNSView(context:Context)->BodyProbeNSView {let view=BodyProbeNSView();view.identifier=NSUserInterfaceItemIdentifier("fixture-body");return view}
func updateNSView(_ view:BodyProbeNSView,context:Context) {}
}
enum ComposeMode {case newMessage;case reply(messageID:UUID,accountID:UUID);case replyAll(messageID:UUID,accountID:UUID);case forward(messageID:UUID,accountID:UUID)}
final class AppDelegate:NSObject,NSApplicationDelegate {func openCompose(mode:ComposeMode){}}
final class MUAResolverClient {struct Resolved {let pngData:Data?;let displayName:String}; static let shared=MUAResolverClient(); func resolve(userAgent:String) async->Resolved? {nil}}
struct Attachment:Identifiable {let id=UUID();var filename:String;var mimeType="application/octet-stream";var size:Int64=100;var localPath:String?;var isInline=false}
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
var fullMessage=Message();fullMessage.subject=String(repeating:"Subject 主题\\n",count:100)
fullMessage.toAddresses=(1...100).map {"recipient \\($0)@example.test"}
let fullAttachments=(1...100).map {Attachment(filename:"File \\($0).txt")}
env.syncService.message=fullMessage;env.syncService.attachments=fullAttachments
var fullEml=EmailMessage();fullEml.subject=fullMessage.subject;fullEml.to=fullMessage.toAddresses.compactMap(EmailAddress.init)
func descendants(_ view:NSView)->[NSView] {view.subviews.flatMap {[$0]+descendants($0)}}
func checkWindow<V:View>(_ content:V, title:String) {
let window=NSWindow(contentRect:NSRect(x:0,y:0,width:500,height:400),styleMask:[.titled,.closable,.resizable],backing:.buffered,defer:false)
window.autorecalculatesKeyViewLoop=true
window.toolbarStyle = .unified
window.toolbar=NSToolbar(identifier:"FixtureReadingToolbar")
let host=NSHostingView(rootView:content);window.contentView=host
window.setFrame(NSRect(x:0,y:0,width:500,height:400),display:false)
for _ in 0..<20 {RunLoop.main.run(until:Date().addingTimeInterval(0.02));host.layoutSubtreeIfNeeded()}
let body=descendants(host).first {$0.identifier?.rawValue=="fixture-body"}!
let bodyFrame=host.convert(body.bounds,from:body)
print("FULL WINDOW",title,"window",window.frame,"layout",window.contentLayoutRect,"content",host.bounds,"body",bodyFrame)
precondition(bodyFrame.height>=70 && bodyFrame.width>=400,"Reading body must retain useful space in a minimum-size native window")
precondition(bodyFrame.minY>=0 && bodyFrame.maxY<=host.bounds.maxY+1)
}
checkWindow(MessageDetailView(messageID:fullMessage.id).environment(env).environment(state),title:"message")
checkWindow(EmlViewerView(email:fullEml,attachments:fullAttachments,inlineRefs:[]),title:"EML")

}
}
'''
with tempfile.TemporaryDirectory(prefix='emailx-reading-layout-') as d:
 p=Path(d);(p/'stubs.swift').write_text(stubs);(p/'probe.swift').write_text(probe)
 header=Path('MyEmail/Views/MessageHeaderBar.swift').read_text().replace('import SwiftMail\n','').replace('SwiftMail.EmailAddress','EmailAddress')
 (p/'MessageHeaderBar.swift').write_text(header)
 eml_source=Path('MyEmail/Views/EmlViewerView.swift').read_text().replace('import SwiftEmailParser\n','').replace('private struct EmlViewerHeader','struct EmlViewerHeader',1)
 (p/'EmlViewerView.swift').write_text(eml_source)
 for name in ['MessageDetailView','RemoteContentBanner']:
  source=Path(f'MyEmail/Views/{name}.swift').read_text().replace('import SwiftMail\n','')
  (p/f'{name}.swift').write_text(source)
 subprocess.run(['xcrun','swiftc','-parse-as-library','-module-name','MyEmail',str(p/'stubs.swift'),str(p/'MessageHeaderBar.swift'),str(p/'EmlViewerView.swift'),str(p/'MessageDetailView.swift'),str(p/'RemoteContentBanner.swift'),'MyEmail/Views/RawSourceView.swift','MyEmail/Views/InitialsAvatarView.swift','MyEmail/Utilities/FlowLayout.swift','MyEmail/Views/AttachmentStripView.swift',str(p/'probe.swift'),'-o',str(p/'probe')],check=True)
 subprocess.run([str(p/'probe')],check=True)
