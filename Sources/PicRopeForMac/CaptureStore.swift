import AppKit
import Combine

/// 一张被“挂上绳子”的截图
final class CaptureItem: Identifiable {
    let id: UUID
    let image: NSImage        // 展示用图像
    let data: Data            // 原始 PNG 数据（复制/拖拽/落盘用）
    let hash: String          // 内容去重
    let source: String        // 来源描述："剪贴板" 或文件路径
    let createdAt: Date
    /// 从磁盘恢复时保留原文件名，否则删除时对不上文件
    private let storedFileName: String?
    var fileName: String {
        storedFileName ?? "\(Int(createdAt.timeIntervalSince1970))-\(id.uuidString).png"
    }

    init?(image: NSImage, source: String) {
        guard let tiff = image.tiffRepresentation,
              let rep = NSBitmapImageRep(data: tiff),
              let png = rep.representation(using: .png, properties: [:]) else { return nil }
        self.id = UUID()
        self.image = image
        self.data = png
        self.hash = CaptureItem.digest(png)
        self.source = source
        self.createdAt = Date()
        self.storedFileName = nil
    }

    init?(pngData: Data, source: String, createdAt: Date = Date(), fileName: String? = nil) {
        guard let image = NSImage(data: pngData) else { return nil }
        self.id = UUID()
        self.image = image
        self.data = pngData
        self.hash = CaptureItem.digest(pngData)
        self.source = source
        self.createdAt = createdAt
        self.storedFileName = fileName
    }

    private static func digest(_ data: Data) -> String {
        String(format: "%x%x%x%x", data.count,
               data.prefix(8).reduce(0) { $0 &* 31 &+ Int($1) },
               data.dropFirst(data.count / 2).prefix(8).reduce(0) { $0 &* 31 &+ Int($1) },
               data.suffix(8).reduce(0) { $0 &* 31 &+ Int($1) })
    }
}

/// 全部截图的内存仓库 + 本地持久化（重启恢复）
final class CaptureStore {
    static let shared = CaptureStore()

    /// 截图落盘目录
    static var storeDir: URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory,
                                            in: .userDomainMask).first!
            .appendingPathComponent("PicRopeForMac/captures", isDirectory: true)
        try? FileManager.default.createDirectory(at: base, withIntermediateDirectories: true)
        return base
    }

    private(set) var items: [CaptureItem] = []
    private let maxItems = 50   // 绳子只保留最近 50 张（对齐 PicRope 规则）
    private var hashes = Set<String>()
    private let queue = DispatchQueue(label: "PicRope.store")

    let changes = PassthroughSubject<Void, Never>()

    /// 收藏的截图（按文件名记录）：不会被自动清理、清空或超量淘汰，只能单独删除
    private var starred = Set(UserDefaults.standard.stringArray(forKey: "starredFiles") ?? [])

    private init() {
        loadPersisted()
    }

    // MARK: - 收藏

    func isStarred(_ item: CaptureItem) -> Bool { starred.contains(item.fileName) }

    func toggleStar(_ item: CaptureItem) {
        if starred.contains(item.fileName) {
            starred.remove(item.fileName)
        } else {
            starred.insert(item.fileName)
        }
        saveStarred()
        changes.send()
    }

    private func saveStarred() {
        UserDefaults.standard.set(Array(starred), forKey: "starredFiles")
    }

    /// 超量时挑出要淘汰的：先挑最旧的未收藏，全是收藏时才动收藏
    private func evictions(from list: [CaptureItem], count: Int) -> [CaptureItem] {
        guard count > 0 else { return [] }
        let plain = list.filter { !starred.contains($0.fileName) }
        let kept = list.filter { starred.contains($0.fileName) }
        return Array((plain + kept).prefix(count))
    }

    // MARK: - 自动清理

    /// 删除超过保留时长且未收藏的截图
    func purgeExpired() {
        let hours = Settings.expireHours
        guard hours > 0 else { return }
        let base = Settings.expiryBaseDate
        let cutoff = Date().addingTimeInterval(-Double(hours) * 3600)
        var removed: [CaptureItem] = []
        queue.sync {
            removed = items.filter { !starred.contains($0.fileName) && max($0.createdAt, base) < cutoff }
            let ids = Set(removed.map(\.id))
            items.removeAll { ids.contains($0.id) }
            removed.forEach {
                hashes.remove($0.hash)
                try? FileManager.default.removeItem(at: fileURL($0))
            }
        }
        if !removed.isEmpty { changes.send() }
    }

    // MARK: - 持久化

    private func fileURL(_ item: CaptureItem) -> URL {
        CaptureStore.storeDir.appendingPathComponent(item.fileName)
    }

    /// 启动时从磁盘恢复
    private func loadPersisted() {
        let dir = CaptureStore.storeDir
        let names = (try? FileManager.default.contentsOfDirectory(atPath: dir.path)) ?? []
        let sorted = names
            .filter { $0.hasSuffix(".png") }
            .sorted { $0 < $1 }   // 文件名前缀是时间戳，字典序即时间序
        var loaded: [CaptureItem] = []
        for name in sorted {
            let ts = Double(name.prefix { $0.isNumber }) ?? 0
            guard ts > 0,
                  let data = try? Data(contentsOf: dir.appendingPathComponent(name)),
                  let item = CaptureItem(pngData: data, source: "上次会话",
                                         createdAt: Date(timeIntervalSince1970: ts),
                                         fileName: name) else { continue }
            guard !hashes.contains(item.hash) else { continue }
            hashes.insert(item.hash)
            loaded.append(item)
        }
        // 只恢复最近 maxItems 张（优先淘汰未收藏的）
        let drop = evictions(from: loaded, count: loaded.count - maxItems)
        let dropIDs = Set(drop.map(\.id))
        drop.forEach { try? FileManager.default.removeItem(at: fileURL($0)) }
        loaded.removeAll { dropIDs.contains($0.id) }
        items = loaded
    }

    /// 新增并落盘
    func add(_ item: CaptureItem) {
        var inserted = false
        queue.sync {
            guard !hashes.contains(item.hash) else { return }
            hashes.insert(item.hash)
            items.append(item)
            inserted = true
            NSLog("[PicRope] 挂上绳子: %@ (%d bytes)", item.source, item.data.count)
            try? item.data.write(to: fileURL(item))
            if items.count > maxItems {
                let removed = evictions(from: items.filter { $0.id != item.id },
                                        count: items.count - maxItems)
                let ids = Set(removed.map(\.id))
                items.removeAll { ids.contains($0.id) }
                removed.forEach { hashes.remove($0.hash) }
                // 淘汰的同时删除对应磁盘文件
                removed.forEach { try? FileManager.default.removeItem(at: fileURL($0)) }
            }
        }
        guard inserted else { return }
        changes.send()
        NotificationCenter.default.post(name: .picRopeItemAdded, object: nil)
    }

    /// 移除并删除磁盘文件
    func remove(_ item: CaptureItem) {
        queue.sync {
            items.removeAll { $0.id == item.id }
            hashes.remove(item.hash)
            try? FileManager.default.removeItem(at: fileURL(item))
        }
        if starred.remove(item.fileName) != nil { saveStarred() }
        changes.send()
    }

    /// 移除除指定图片和收藏外的所有图片（含本地缓存）
    func removeAll(except keep: CaptureItem) {
        queue.sync {
            let removed = items.filter { $0.id != keep.id && !starred.contains($0.fileName) }
            removed.forEach { try? FileManager.default.removeItem(at: fileURL($0)) }
            let ids = Set(removed.map(\.id))
            items.removeAll { ids.contains($0.id) }
            hashes = Set(items.map(\.hash))
        }
        changes.send()
    }

    /// 清空绳子上未收藏的图片（同时清空本地缓存），收藏的保留
    func clear() {
        queue.sync {
            let removed = items.filter { !starred.contains($0.fileName) }
            removed.forEach { try? FileManager.default.removeItem(at: fileURL($0)) }
            items.removeAll { !starred.contains($0.fileName) }
            hashes = Set(items.map(\.hash))
        }
        changes.send()
    }
}
