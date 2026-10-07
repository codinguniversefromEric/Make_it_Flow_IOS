//
//  SettingsView.swift
//  ePdfUB
//
//  Production settings panel — all debug & engine controls live here.
//

import SwiftUI

// MARK: - 主畫面

// 應用程式設定畫面
struct SettingsView: View {
    @ObservedObject var settings = AppSettings.shared
    @Environment(\.dismiss) private var dismiss
    
    var body: some View {
        NavigationView {
            List {

                // MARK: - 開發者與視覺模型 (合併)
                #if DEBUG
                    Section {
                        // Vision 部分
                        Picker(selection: $settings.selectedModel) {
                            ForEach(VisionModelType.allCases) { model in
                                Text(model.rawValue).tag(model)
                            }
                        } label: {
                            Label("Vision Architecture", systemImage: "eye.trianglebadge.exclamationmark")
                        }
                        .pickerStyle(.navigationLink)
                        
                        // 開發者部分
                        Toggle(isOn: $settings.debugMode) {
                            Label("Developer Diagnostics", systemImage: "ladybug")
                        }
                        .tint(.orange)
                        .accessibilityLabel("Developer Diagnostics")
                        .accessibilityHint("Toggle visual diagnostic overlays showing YOLO bounding boxes")
                        
                }
                
                #endif
                
                // MARK: - 關於
                Section {
                    HStack {
                        Label("Version", systemImage: "info.circle")
                        Spacer()
                        Text("3.0.0")
                            .foregroundStyle(.secondary)
                    }
                    
                    Link(destination: URL(string: "https://github.com/codinguniversefromEric/ePdfUB.git")!) {
                        HStack {
                            Label("Open Source & Licenses", systemImage: "link")
                                .foregroundStyle(.primary)
                            Spacer()
                            Image(systemName: "arrow.up.right")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                } header: {
                    Text("ABOUT")
                }
            }
            .navigationTitle("Preferences")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { dismiss() }
                        .fontWeight(.semibold)
                }
            }
        }
    }
}
