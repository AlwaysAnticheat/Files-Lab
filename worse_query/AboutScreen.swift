// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (c) 2026 Files Lab contributors

import SwiftUI

struct AboutScreen: View {
    private var version: String {
        let name = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "—"
        let build = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "—"
        return "\(name) (\(build))"
    }
    private var systemVersion: String {
        if ScreenshotData.enabled { return "iOS 26 or later" }
        let os = ProcessInfo.processInfo.operatingSystemVersion
        return "iOS \(os.majorVersion).\(os.minorVersion).\(os.patchVersion)"
    }

    var body: some View {
        Form {
            Section {
                HStack(spacing: 14) {
                    Image(systemName: "folder.fill")
                        .font(.system(size: 38)).foregroundStyle(.blue)
                    VStack(alignment: .leading, spacing: 3) {
                        Text("Files Lab").font(.title2.weight(.semibold))
                        Text("A file browser built on worse_query")
                            .font(.subheadline).foregroundStyle(.secondary)
                    }
                    .padding(.vertical, 6)
                }
                LabeledContent("Version", value: version)
                LabeledContent("Device Software", value: systemVersion)
            }

            Section("Original Exploit & Developer") {
                LabeledContent("Exploit", value: "worse_query")
                LabeledContent("Original Author", value: "Taj C (forcequit)")
                LabeledContent("GitHub", value: "forcequitOS")
                LabeledContent("Path Enumeration", value: "pathleak, by the same author")
            }

            Section("Credit & Attribution") {
                Text("Files Lab was built using worse_query, the sandbox-escape proof of concept created by Taj C (forcequit / forcequitOS). All credit for the exploit and its original implementation belongs to the original author.")
                Text("We created the file-browsing interface and integration. We did not discover, invent, or create this exploit. Files Lab is an independent modification and does not represent the original author.")
                    .fontWeight(.medium)
            }

            Section("Original Project") {
                Link(destination: URL(string: "https://github.com/forcequitOS/worse_query")!) {
                    Label("worse_query Source", systemImage: "arrow.up.right.square")
                }
                Link(destination: URL(string: "https://github.com/forcequitOS")!) {
                    Label("Original Developer", systemImage: "person.crop.circle")
                }
                LabeledContent("Source Revision", value: "d1540e2")
            }

            Section("Open Source") {
                Text("Distributed under GPL v3 or later, without warranty. See the license for copying and modification terms.")
                    .font(.footnote).foregroundStyle(.secondary)
                Text("Original exploit and enumeration code: Copyright © 2026 Taj C (forcequit).")
                    .font(.footnote).foregroundStyle(.secondary)
                NavigationLink {
                    OpenSourceLicenseScreen()
                } label: {
                    LabeledContent("License", value: "GPL v3 or later")
                }
            }
        }
        .navigationTitle("About")
    }
}

private struct OpenSourceLicenseScreen: View {
    private var license: String {
        guard let url = Bundle.main.url(forResource: "License", withExtension: "txt"),
              let text = try? String(contentsOf: url, encoding: .utf8) else {
            return "The GNU General Public License is available in the original project's source repository."
        }
        return text
    }
    var body: some View {
        ScrollView {
            Text(license).font(.footnote).textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading).padding()
        }
        .navigationTitle("Open-Source License")
        .navigationBarTitleDisplayMode(.inline)
    }
}
