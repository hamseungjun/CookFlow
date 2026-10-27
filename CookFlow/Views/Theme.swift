import SwiftUI

enum Palette {
    static let background = Color(red: 0.97, green: 0.96, blue: 0.93)
    static let ink = Color(red: 0.14, green: 0.20, blue: 0.17)
    static let green = Color(red: 0.19, green: 0.36, blue: 0.27)
    static let muted = Color(red: 0.38, green: 0.43, blue: 0.39)
    static let orange = Color(red: 0.68, green: 0.29, blue: 0.10)
}
struct Card<Content: View>: View {
    @ViewBuilder var content: Content
    var body: some View { content.padding(20).frame(maxWidth: .infinity, alignment: .leading).background(.white, in: RoundedRectangle(cornerRadius: 12)).overlay(RoundedRectangle(cornerRadius: 12).stroke(Palette.ink.opacity(0.06))) }
}
struct PrimaryButton: View {
    var title: String
    var icon: String = "arrow.right"
    var action: () -> Void
    var body: some View { Button(action: action) { HStack { Text(title); Spacer(); Image(systemName: icon) }.font(.headline).padding(.horizontal, 20).frame(maxWidth: .infinity).padding(.vertical, 18).foregroundStyle(.white).background(Palette.green, in: RoundedRectangle(cornerRadius: 10)).contentShape(Rectangle()) }.buttonStyle(.plain) }
}
struct SectionTitle: View {
    var title: String
    var subtitle: String = ""
    var body: some View { VStack(alignment: .leading, spacing: 8) { Text(title).font(.system(.title, design: .serif, weight: .semibold)).foregroundStyle(Palette.ink); if !subtitle.isEmpty { Text(subtitle).font(.subheadline).foregroundStyle(Palette.muted) } }.frame(maxWidth: .infinity, alignment: .leading) }
}
struct Tag: View {
    var text: String
    var icon: String?
    var body: some View { HStack(spacing: 5) { if let icon { Image(systemName: icon) }; Text(text) }.font(.caption.weight(.semibold)).padding(.horizontal, 11).padding(.vertical, 7).background(Palette.green.opacity(0.09), in: Capsule()).foregroundStyle(Palette.green) }
}
struct EmptyState: View {
    var icon: String; var title: String; var detail: String
    var body: some View { VStack(spacing: 18) { Image(systemName: icon).font(.system(size: 46)).foregroundStyle(Palette.green); Text(title).font(.title2.bold()); Text(detail).foregroundStyle(Palette.muted).multilineTextAlignment(.center) }.frame(maxWidth: .infinity).padding(40) }
}
