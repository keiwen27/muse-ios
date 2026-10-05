import SwiftUI
import MapKit
import AVFoundation

/// 幻灯片编辑器（对齐原版内嵌幻灯片编辑：增删页/改内容/导出）
struct SlidesEditorSheet: View {
    @EnvironmentObject private var store: AppStore
    @Environment(\.dismiss) private var dismiss
    @State var slides: [Slide]
    @State private var selected = 0
    @State private var shareURL: URL?

    var body: some View {
        NavigationView {
            VStack(spacing: 0) {
                if slides.isEmpty {
                    Text("没有幻灯片")
                        .foregroundColor(Theme.textSecondary)
                } else {
                    // 页指示
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 6) {
                            ForEach(Array(slides.enumerated()), id: \.offset) { idx, slide in
                                Button {
                                    selected = idx
                                } label: {
                                    Text("\(idx + 1). \(slide.title)")
                                        .font(.caption)
                                        .lineLimit(1)
                                        .padding(.horizontal, 10).padding(.vertical, 6)
                                        .background(RoundedRectangle(cornerRadius: 8)
                                            .fill(selected == idx ? Theme.accent : Theme.surface2))
                                        .foregroundColor(selected == idx ? .white : Theme.textSecondary)
                                }
                            }
                        }
                        .padding(.horizontal, 12)
                    }
                    .padding(.vertical, 8)

                    // 页编辑
                    Form {
                        Section("第 \(selected + 1) 页") {
                            TextField("页面标题", text: $slides[selected].title)
                                .foregroundColor(Theme.textPrimary)
                        }
                        Section("要点（每行一条）") {
                            TextEditor(text: binding(for: selected))
                                .frame(minHeight: 160)
                        }
                        Section {
                            Button("添加页") {
                                slides.append(Slide(title: "第 \(slides.count + 1) 页", bullets: ["要点…"]))
                                selected = slides.count - 1
                            }
                            .foregroundColor(Theme.accent)
                            Button("删除本页", role: .destructive) {
                                guard slides.count > 1 else { return }
                                slides.remove(at: selected)
                                selected = max(0, selected - 1)
                            }
                            .foregroundColor(Theme.danger)
                        }
                    }
                }
            }
            .navigationTitle("幻灯片编辑器")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("完成") {
                        store.data.settings.slidesEditorActive = false
                        store.save()
                        dismiss()
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("导出") {
                        let dir = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
                        let fmt = DateFormatter()
                        fmt.dateFormat = "yyyyMMdd-HHmmss"
                        let url = dir.appendingPathComponent("muse-slides-\(fmt.string(from: Date())).md")
                        let text = slides.map { s in
                            "## \(s.title)\n" + s.bullets.map { "- \($0)" }.joined(separator: "\n")
                        }.joined(separator: "\n\n")
                        try? Data(text.utf8).write(to: url)
                        shareURL = url
                    }
                }
            }
            .sheet(isPresented: Binding(get: { shareURL != nil }, set: { if !$0 { shareURL = nil } })) {
                if let url = shareURL { ShareSheet(items: [url]) }
            }
        }
        .navigationViewStyle(.stack)
    }

    private func binding(for index: Int) -> Binding<String> {
        Binding(
            get: { slides[index].bullets.joined(separator: "\n") },
            set: { slides[index].bullets = $0.split(separator: "\n").map(String.init) })
    }
}

/// 地图视图（对齐原版「周边地点/正在加载导航」，MapKit 实现）
struct MapSheet: View {
    @EnvironmentObject private var store: AppStore
    @Environment(\.dismiss) private var dismiss
    @State private var region = MKCoordinateRegion(
        center: CLLocationCoordinate2D(latitude: 39.9042, longitude: 116.4074),
        span: MKCoordinateSpan(latitudeDelta: 0.05, longitudeDelta: 0.05))
    @State private var annotationTitle = ""

    var body: some View {
        NavigationView {
            ZStack {
                Map(coordinateRegion: $region,
                    annotationItems: annotations) { item in
                    MapMarker(coordinate: item.coordinate, tint: Theme.accent)
                }
                .ignoresSafeArea(edges: .bottom)
            }
            .navigationTitle("地图 · \(store.lastMapQuery ?? "")")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("完成") {
                        store.lastMapQuery = nil
                        dismiss()
                    }
                }
            }
        }
        .navigationViewStyle(.stack)
        .onAppear(perform: geocode)
    }

    private var annotations: [MapPin] {
        guard let q = store.lastMapQuery else { return [] }
        return [MapPin(name: q, coordinate: region.center)]
    }

    private func geocode() {
        guard let q = store.lastMapQuery else { return }
        let geocoder = CLGeocoder()
        geocoder.geocodeAddressString(q) { placemarks, _ in
            if let loc = placemarks?.first?.location {
                region = MKCoordinateRegion(
                    center: loc.coordinate,
                    span: MKCoordinateSpan(latitudeDelta: 0.05, longitudeDelta: 0.05))
                annotationTitle = q
            }
        }
    }
}

struct MapPin: Identifiable {
    var id = UUID()
    var name: String
    var coordinate: CLLocationCoordinate2D
}

/// 年龄验证 Sheet（对齐原版「正在打开年龄验证…」）
struct AgeVerificationSheet: View {
    @EnvironmentObject private var store: AppStore
    @Environment(\.dismiss) private var dismiss
    @State private var birthYear = ""
    @State private var hint = ""

    var body: some View {
        NavigationView {
            Form {
                Section {
                    Text("购物与代买功能需要完成年龄验证。输入出生年份完成验证（本地演示流程）。")
                        .font(.footnote)
                        .foregroundColor(Theme.textSecondary)
                    TextField("出生年份（如 1995）", text: $birthYear)
                        .keyboardType(.numberPad)
                    if !hint.isEmpty {
                        Text(hint).font(.footnote).foregroundColor(Theme.danger)
                    }
                }
                Section {
                    Button("完成验证") {
                        guard let y = Int(birthYear), (1900...Calendar.current.component(.year, from: Date())).contains(y) else {
                            hint = "请输入有效的出生年份"
                            return
                        }
                        let age = Calendar.current.component(.year, from: Date()) - y
                        if age < 18 {
                            hint = "未满 18 周岁，无法使用购物与代买功能。"
                            return
                        }
                        store.completeAgeVerification()
                        store.data.settings.ageGateActive = false
                        store.save()
                        dismiss()
                    }
                    .foregroundColor(Theme.accent)
                    Button("稍后再说", role: .cancel) {
                        store.data.settings.ageGateActive = false
                        store.save()
                        dismiss()
                    }
                    .foregroundColor(Theme.textSecondary)
                }
            }
            .navigationTitle("年龄验证")
            .navigationBarTitleDisplayMode(.inline)
        }
        .navigationViewStyle(.stack)
    }
}
