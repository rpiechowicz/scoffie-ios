import SwiftUI
import UIKit
import ImageIO
import CryptoKit

private enum CachedAsyncImageError: Error {
    case invalidImageData
}

private final class SharedImageMemoryCache {
    static let shared = SharedImageMemoryCache()

    private let cache: NSCache<NSURL, UIImage> = {
        let cache = NSCache<NSURL, UIImage>()
        cache.countLimit = 512
        cache.totalCostLimit = 128 * 1_024 * 1_024
        return cache
    }()

    private init() { }

    func image(for url: URL) -> UIImage? {
        cache.object(forKey: url as NSURL)
    }

    func insert(_ image: UIImage, for url: URL) {
        let pixelCount = image.size.width * image.size.height * image.scale * image.scale
        let cost = max(1, Int(pixelCount * 4))
        cache.setObject(image, forKey: url as NSURL, cost: cost)
    }
}

// Trwały cache zakodowanych bajtów (JPEG/PNG z serwera) na dysku, niezależny od
// nagłówków Cache-Control backendu — dzięki temu drugie uruchomienie aplikacji
// serwuje okładki z dysku zamiast sieci, bez „wyskakiwania” obrazów.
private final class SharedImageDiskCache {
    static let shared = SharedImageDiskCache()

    private let directory: URL
    private let fileManager = FileManager.default
    private let ioQueue = DispatchQueue(label: "app.scoffie.imagecache.disk", qos: .utility)
    private let maxDiskBytes: Int = 300 * 1_024 * 1_024
    private let maxAge: TimeInterval = 60 * 60 * 24 * 30

    /// Wersja katalogu na dysku. Podbicie unieważnia CAŁY cache obrazów.
    ///
    /// Cache kluczuje po URL-u, więc nie ma jak zauważyć, że pod tym samym
    /// adresem serwer podmienił zawartość — a dokładnie to zdarzyło się przy
    /// prostowaniu id przepisów: przez chwilę pod adresem `<id>.png` leżało
    /// zdjęcie innego dania i telefony zdążyły je sobie zapisać. Numer w
    /// nazwie katalogu jest jedynym sposobem, żeby kazać im pobrać wszystko
    /// od nowa; sam czas nie wystarczy, bo wpis żyje 30 dni.
    private static let directoryName = "app.scoffie.imagecache.v1"

    private init() {
        let base = fileManager.urls(for: .cachesDirectory, in: .userDomainMask)[0]
        directory = base.appendingPathComponent(Self.directoryName, isDirectory: true)
        try? fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
        ioQueue.async { [weak self] in
            self?.removeStaleVersions(in: base)
            self?.pruneIfNeeded()
        }
    }

    /// Kasuje katalogi po poprzednich wersjach cache'u. Bez tego każde
    /// podbicie zostawia na dysku użytkownika kilkaset megabajtów, których
    /// nic już nie czyta i których `pruneIfNeeded` nie widzi — patrzy tylko
    /// do katalogu bieżącej wersji.
    private func removeStaleVersions(in base: URL) {
        guard let contents = try? fileManager.contentsOfDirectory(
            at: base,
            includingPropertiesForKeys: nil
        ) else { return }

        for url in contents
        where url.lastPathComponent.hasPrefix("app.scoffie.imagecache.")
            && url.lastPathComponent != Self.directoryName {
            try? fileManager.removeItem(at: url)
        }
    }

    func data(for url: URL) -> Data? {
        let path = filePath(for: url)
        guard let data = try? Data(contentsOf: path, options: .mappedIfSafe) else { return nil }
        ioQueue.async { [weak self] in
            try? self?.fileManager.setAttributes([.modificationDate: Date()], ofItemAtPath: path.path)
        }
        return data
    }

    func insert(_ data: Data, for url: URL) {
        let path = filePath(for: url)
        ioQueue.async { [weak self] in
            try? data.write(to: path, options: .atomic)
            self?.pruneIfNeeded()
        }
    }

    private func filePath(for url: URL) -> URL {
        let digest = SHA256.hash(data: Data(url.absoluteString.utf8))
        let name = digest.map { String(format: "%02x", $0) }.joined()
        return directory.appendingPathComponent(name)
    }

    private func pruneIfNeeded() {
        let keys: [URLResourceKey] = [.contentModificationDateKey, .fileSizeKey]
        guard let contents = try? fileManager.contentsOfDirectory(
            at: directory,
            includingPropertiesForKeys: keys
        ) else { return }

        let now = Date()
        var entries: [(url: URL, date: Date, size: Int)] = []
        var total = 0

        for file in contents {
            let values = try? file.resourceValues(forKeys: Set(keys))
            let date = values?.contentModificationDate ?? now
            let size = values?.fileSize ?? 0
            if now.timeIntervalSince(date) > maxAge {
                try? fileManager.removeItem(at: file)
                continue
            }
            total += size
            entries.append((file, date, size))
        }

        guard total > maxDiskBytes else { return }
        for entry in entries.sorted(by: { $0.date < $1.date }) {
            try? fileManager.removeItem(at: entry.url)
            total -= entry.size
            if total <= maxDiskBytes { break }
        }
    }
}

private actor SharedImagePipeline {
    static let shared = SharedImagePipeline()

    // Mały memory-only URLCache — trwałość HTTP zastąpiliśmy własnym dyskiem
    // (SharedImageDiskCache), który nie zależy od Cache-Control z backendu.
    private nonisolated let session: URLSession = {
        let config = URLSessionConfiguration.default
        config.urlCache = URLCache(memoryCapacity: 8 * 1_024 * 1_024, diskCapacity: 0, diskPath: nil)
        config.requestCachePolicy = .useProtocolCachePolicy
        config.httpMaximumConnectionsPerHost = 8
        config.timeoutIntervalForRequest = 30
        config.waitsForConnectivity = true
        return URLSession(configuration: config)
    }()

    // Maks. krawędź thumbnailu (px). 1200 pokrywa zarówno kafelki w siatce, jak
    // i pełnoekranowy header szczegółów na iPhone'ach — i pozwala uniknąć
    // dekodowania 3–5 MP bitmap tylko po to, żeby SwiftUI je pomniejszył.
    private static let maxThumbnailPixelSize: CGFloat = 1200

    private var inFlight: [URL: Task<UIImage, Error>] = [:]

    func image(for url: URL) async throws -> UIImage {
        if let cached = SharedImageMemoryCache.shared.image(for: url) {
            return cached
        }

        if let task = inFlight[url] {
            return try await task.value
        }

        let task = makeFetchTask(url: url)
        inFlight[url] = task
        defer { inFlight[url] = nil }
        return try await task.value
    }

    func prefetch(_ urls: [URL]) {
        for url in urls {
            guard SharedImageMemoryCache.shared.image(for: url) == nil,
                  inFlight[url] == nil else { continue }
            // Reuse ten sam tor co zwykły fetch — defer w image(for:) sprząta inFlight,
            // więc nie ma ryzyka wyścigu z równoległym zapotrzebowaniem na ten sam URL.
            Task { [weak self] in
                _ = try? await self?.image(for: url)
            }
        }
    }

    private func makeFetchTask(url: URL) -> Task<UIImage, Error> {
        let session = self.session
        return Task.detached(priority: .userInitiated) {
            if let data = SharedImageDiskCache.shared.data(for: url),
               let decoded = await Self.decode(data: data) {
                SharedImageMemoryCache.shared.insert(decoded, for: url)
                return decoded
            }

            let (data, _) = try await session.data(from: url)
            guard let decoded = await Self.decode(data: data) else {
                throw CachedAsyncImageError.invalidImageData
            }
            SharedImageMemoryCache.shared.insert(decoded, for: url)
            SharedImageDiskCache.shared.insert(data, for: url)
            return decoded
        }
    }

    private static func decode(data: Data) async -> UIImage? {
        let image: UIImage? = {
            guard let source = CGImageSourceCreateWithData(data as CFData, nil) else {
                return UIImage(data: data)
            }
            let options: [CFString: Any] = [
                kCGImageSourceCreateThumbnailFromImageAlways: true,
                kCGImageSourceShouldCacheImmediately: true,
                kCGImageSourceCreateThumbnailWithTransform: true,
                kCGImageSourceThumbnailMaxPixelSize: maxThumbnailPixelSize
            ]
            guard let cg = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary) else {
                return UIImage(data: data)
            }
            return UIImage(cgImage: cg)
        }()

        guard let image else { return nil }
        // byPreparingForDisplay dekoduje poza main threadem — bez tego pierwszy render
        // obrazu blokuje scroll i wywołuje efekt „wyskakiwania”.
        return await image.byPreparingForDisplay() ?? image
    }
}

/// Warmuje cache obrazów dla przyszłych widoków — wołaj gdy znasz URL-e wcześniej
/// niż pojawią się na ekranie (np. po załadowaniu listy przepisów / stronicowaniu).
enum ImagePrefetcher {
    static func prefetch(_ urls: [URL]) {
        guard !urls.isEmpty else { return }
        Task.detached(priority: .utility) {
            await SharedImagePipeline.shared.prefetch(urls)
        }
    }

    /// Jak `prefetch`, ale czeka aż pierwsza partia miniaturek zostanie zdekodowana
    /// i będzie w cache pamięciowym. Używane przez smart startup loader, żeby
    /// lista przepisów nie „wyskakiwała” okładkami zaraz po wejściu.
    static func prefetchAwaiting(_ urls: [URL]) async {
        guard !urls.isEmpty else { return }
        await withTaskGroup(of: Void.self) { group in
            for url in urls {
                group.addTask(priority: .userInitiated) {
                    _ = try? await SharedImagePipeline.shared.image(for: url)
                }
            }
        }
    }
}

struct CachedAsyncImage<Content: View>: View {
    private let url: URL?
    private let content: (AsyncImagePhase) -> Content

    @State private var phase: AsyncImagePhase

    init(url: URL?, @ViewBuilder content: @escaping (AsyncImagePhase) -> Content) {
        self.url = url
        self.content = content
        _phase = State(initialValue: Self.initialPhase(for: url))
    }

    var body: some View {
        content(phase)
            // Reset synchroniczny przy zmianie URL (LazyVGrid podmienia content w recyklowanej komórce):
            // bez tego widać na klatkę starą okładkę z poprzedniego recipe.
            .onChange(of: url, initial: false) { _, newURL in
                phase = Self.initialPhase(for: newURL)
            }
            .task(id: url) {
                await loadImage()
            }
    }

    private func loadImage() async {
        guard let url else {
            phase = .empty
            return
        }

        if case .success = phase {
            return
        }

        do {
            let image = try await SharedImagePipeline.shared.image(for: url)
            // Zdjęcie, które przyszło PO pierwszej klatce, wchodzi kryciem
            // zamiast wskakiwać w miejsce zastępczego gradientu. Trafienie
            // w pamięć podręczną tu nie dociera (`initialPhase` oddaje sukces
            // synchronicznie), więc animuje się wyłącznie prawdziwe
            // doładowanie — z dysku albo z sieci — i tylko ono mogło mignąć.
            withAnimation(.smooth(duration: 0.25)) {
                phase = .success(Image(uiImage: image))
            }
        } catch is CancellationError {
            return
        } catch {
            phase = .failure(error)
        }
    }

    private static func initialPhase(for url: URL?) -> AsyncImagePhase {
        guard let url, let image = SharedImageMemoryCache.shared.image(for: url) else {
            return .empty
        }

        return .success(Image(uiImage: image))
    }
}
