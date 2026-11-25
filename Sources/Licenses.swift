import SwiftUI

/// Open-source notice. FoldArc is distributed under GPLv3 because the 3DS
/// core it embeds (Azahar) is GPL; the notice must be reachable from the app
/// itself. The component list follows NOTICE.md (checked against the core's
/// link line on 10-28). Keep the wording factual: no games, keys or system files ship
/// with the app, and nothing here is affiliated with any console maker.
enum OpenSourceNotice {
    static let summary = String(localized: """
    Zero EMU 以 GNU General Public License v3.0（GPLv3）发布。你可以依许可证自由使用、研究、修改和再分发；完整对应源码见下方仓库链接。

    本 App 不包含任何游戏、密钥、固件或主机系统文件，也不提供它们的下载或链接；它只能加载你自己拥有、不带加密保护、通过系统"文件"选择器导入的文件。Zero EMU 与任何游戏主机厂商没有关联。
    """)
    /// The core in the bundle (系统设置 › 关于本机 names it without loading it).
    static let coreRelease = "Azahar 2126.1.1"
    static let components: [(name: String, license: String)] = [
        (String(localized: "Zero EMU（界面、外壳、Orbit Garden 演示）"), "GPL-3.0-only"),
        (String(localized: "\(coreRelease.replacingOccurrences(of: "Azahar ", with: String(localized: "Azahar 3DS 核心 ")))（含 Zero EMU 的补丁）"), "GPL-2.0-or-later / GPL-3.0"),
        (String(localized: "MoltenVK 1.4.2（Vulkan → Metal）"), "Apache-2.0"),
        ("faad2", "GPL-2.0-or-later"),
        ("SoundTouch", "LGPL-2.1"),
        (String(localized: "Boost、Crypto++"), "BSL-1.0"),
        ("LibreSSL", String(localized: "OpenSSL / SSLeay、ISC")),
        ("dynarmic", "0BSD"),
        (String(localized: "cpp-httplib、nlohmann/json、mcl、oaknut、teakra、enet、fmt、Vulkan Memory Allocator、libretro-common"), "MIT"),
        ("zstd", String(localized: "BSD-3-Clause 或 GPL-2.0")),
        ("xxHash", "BSD-2-Clause"),
        (String(localized: "sirit、nihstro、glslang / SPIRV"), String(localized: "BSD-3-Clause（glslang 另含 Apache-2.0、MIT 等）")),
        ("lodepng", "zlib"),
        (String(localized: "Vulkan-Headers（仅编译期）"), "Apache-2.0 OR MIT"),
        (String(localized: "画框的环境声，金卡带、银卡带短片里的录音（八音盒的单音也是）：BigSoundBank，Joseph Sardin 录制。谢谢！"), String(localized: "CC0（公有领域）")),
        (String(localized: "银卡带短片里的吉他单音：爱荷华大学电子音乐工作室的乐器采样（Raimundo 118 古典吉他，Brian Penkrot 演奏）。谢谢！"),
         String(localized: "可用于任何项目，没有限制"))
    ]
}

/// 11-07: the licence texts themselves, as the MIT / BSD / Apache terms want them
/// shipped with the binary. Sources/ThirdPartyLicenses.txt is gathered from
/// each component's own LICENSE / COPYING by work/r32 job 1101 (one block per
/// component, the blocks fenced with a line of "=" characters: name, licence,
/// the file's path in the source tree, then the text).
enum ThirdPartyLicenses {
    struct Block: Identifiable {
        var id: Int
        var name: String
        var licence: String
        var text: String
    }
    static let blocks: [Block] = {
        guard let url = Bundle.main.url(forResource: "ThirdPartyLicenses", withExtension: "txt"),
              let whole = try? String(contentsOf: url, encoding: .utf8) else { return [] }
        return parse(whole)
    }()
    /// 11-11: the file is read by whole lines (LicenceFile, Domain.swift).
    static func parse(_ whole: String) -> [Block] {
        LicenceFile.parse(whole).enumerated().map { Block(id: $0.offset, name: $0.element.name, licence: $0.element.licence, text: $0.element.text) }
    }
}

struct LicensesView: View {
    var close: () -> Void
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                HStack { Text("开源许可与声明").font(.title2.bold()); Spacer(); Pill(text: "GPLv3") }
                Text(OpenSourceNotice.summary).font(.system(size: 13)).foregroundStyle(Palette.muted)
                    .fixedSize(horizontal: false, vertical: true)
                // The addresses live in AppLinks (Domain.swift); a missing one is
                // left out. Development builds say so for the source link,
                // which the GPL needs before anything ships.
                if let source = AppLinks.source {
                    Link(destination: source) {
                        Label("源码仓库", systemImage: "chevron.left.forwardslash.chevron.right").font(.system(size: 13, weight: .semibold))
                    }
                } else {
                    #if DEBUG
                    Text("源码仓库地址还没填（AppLinks.source），上架前要填。").font(.caption2).foregroundStyle(Palette.orange)
                    #endif
                }
                if let privacy = AppLinks.privacy {
                    Link(destination: privacy) {
                        Label("隐私政策", systemImage: "hand.raised").font(.system(size: 13, weight: .semibold))
                    }
                }
                if let support = AppLinks.support {
                    Link(destination: support) {
                        Label("反馈与支持", systemImage: "bubble.left").font(.system(size: 13, weight: .semibold))
                    }
                }
                VStack(alignment: .leading, spacing: 10) {
                    ForEach(OpenSourceNotice.components, id: \.name) { item in
                        VStack(alignment: .leading, spacing: 3) {
                            Text(item.name).font(.system(size: 12, weight: .semibold))
                            Text(item.license).font(.system(size: 11, design: .monospaced)).foregroundStyle(Palette.muted)
                        }
                    }
                }
                Text("This program comes with ABSOLUTELY NO WARRANTY. See the GNU General Public License for details.")
                    .font(.caption2).foregroundStyle(Palette.muted)
                Button("知道了", action: close).buttonStyle(ActionStyle(primary: true))
            }.padding(28).frame(maxWidth: 520)
        }.background(Palette.background).preferredColorScheme(.dark)
    }
}
