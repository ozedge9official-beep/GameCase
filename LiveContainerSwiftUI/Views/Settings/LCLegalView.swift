// GameCase modification, 2026-11-17: licenses and notices available offline.
import SwiftUI

struct LCLegalView: View {
    private struct Notice: Decodable, Identifiable {
        let title: String
        let file: String
        var id: String { file }
    }
    private struct Index: Decodable {
        let version: String
        let sourceTree: String
        let sourceURL: String
        let repositoryURL: String
        let entries: [Notice]
    }
    private let directory = Bundle.main.bundleURL.appendingPathComponent("GameCaseLegal")
    private var index: Index? {
        guard let data = try? Data(contentsOf: directory.appendingPathComponent("index.json")) else { return nil }
        return try? JSONDecoder().decode(Index.self, from: data)
    }

    var body: some View {
        List {
            if let index {
                Section {
                    ForEach(index.entries) { notice in
                        NavigationLink {
                            ScrollView {
                                Text((try? String(contentsOf: directory.appendingPathComponent(notice.file), encoding: .utf8)) ?? "无法读取许可文本")
                                    .font(.system(.footnote, design: .monospaced))
                                    .textSelection(.enabled)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                    .padding()
                            }
                            .navigationTitle(notice.title)
                        } label: { Text(notice.title) }
                    }
                } header: { Text("离线许可与归属") }
                Section {
                    if let url = URL(string: index.repositoryURL + "/releases/tag/v" + index.version) {
                        Link("此版本的安装包与对应源码", destination: url)
                    }
                    if let url = URL(string: index.sourceURL) {
                        Link("下载对应源码及构建资料", destination: url)
                    }
                    Text("版本 \(index.version) · 源码树 \(index.sourceTree)")
                        .font(.footnote).textSelection(.enabled)
                } footer: {
                    Text("联网链接需要网络。许可全文可离线查看；源码包包含固定依赖和构建说明。测试版源码随对应构建的附件提供。")
                }
            } else {
                Text("此安装包缺少许可资料，请从项目发布页获取完整安装包。")
            }
        }
        .navigationTitle("许可证与源代码")
    }
}
