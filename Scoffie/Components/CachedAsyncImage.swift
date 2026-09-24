import SwiftUI
import UIKit
import ImageIO
import CryptoKit

private enum CachedAsyncImageError: Error {
    case invalidImageData
}

/// W jakiej wielkości ekran potrzebuje zdjęcia.
///
/// Zdjęcia przepisów to PNG 1024×1024: zdekodowane ważą po 4 MB, więc pamięć
/// podręczna mieściła ich około trzydziestu — przy katalogu ponad stu
/// przepisów lista wypychała własne okładki i dekodowała je od nowa przy
/// każdym przewinięciu („przeskakujące" zdjęcia). Miniatura ma 512 px
/// i około 1 MB, więc CAŁY katalog siedzi w pamięci naraz.
enum CachedImageVariant: Sendable {
    /// Wiersze list, kafelki, talerze kalendarza — wszystko do ~170 pt.
    case thumbnail
    /// Okładka szczegółów przepisu i duże karty.
    case large
    /// Pionowy plakat z drobnym tekstem na cały ekran — plansze przewodnika
    /// „Poznaj aplikację” (1080 × 2344). Przy `.large` dłuższy bok schodził
    /// do 1200 px i tekst na plakacie się rozmywał.
    case poster

    var maxPixelSize: CGFloat {
        switch self {
        case .thumbnail: 512
        case .large: 1200
        case .poster: 2400
        }
    }

    fileprivate var cacheSuffix: String {
        switch self {
        case .thumbnail: "#t512"
        case .large: ""
        case .poster: "#p2400"
        }
    }
}

private final class SharedImageMemoryCache: @unchecked Sendable {
    static let shared = SharedImageMemoryCache()

    private let cache: NSCache<NSString, UIImage> = {
        let cache = NSCache<NSString, UIImage>()
        cache.countLimit = 768
        cache.totalCostLimit = 256 * 1_024 * 1_024
        return cache
    }()

    private init() { }

    private func key(_ url: URL, _ variant: CachedImageVariant) -> NSString {
        (url.absoluteString + variant.cacheSuffix) as NSString
    }

    func image(for url: URL, variant: CachedImageVariant) -> UIImage? {
        cache.object(forKey: key(url, variant))
    }

    func insert(_ image: UIImage, for url: URL, variant: CachedImageVariant) {
        let pixelCount = image.size.width * image.size.height * image.scale * image.scale
        let cost = max(1, Int(pixelCount * 4))
        cache.setObject(image, forKey: key(url, variant), cost: cost)
    }
}

/// Ogranicza liczbę zdjęć dekodowanych naraz. Rozgrzewka startowa prosi
/// o cały katalog jednocześnie, a każde PNG 1024² to 4 MB na czas dekodowania
/// — bez bramki ponad sto takich naraz było skokiem pamięci o pół gigabajta.
private actor ImageDecodeGate {
    static let shared = ImageDecodeGate()

    private let limit = 4
    private var running = 0
    private var waiting: [CheckedContinuation<Void, Never>] = []

    func enter() async {
        if running < limit {
            running += 1
            return
        }
        await withCheckedContinuation { waiting.append($0) }
    }

    func leave() {
        if waiting.isEmpty {
            running -= 1
        } else {
            waiting.removeFirst().resume()
        }
    }
}

// Trwały cache zakodowanych bajtów (JPEG/PNG z serwera) na dysku, niezależny od
// nagłówków Cache-Control backendu — dzięki temu drugie uruchomienie aplikacji
// serwuje okładki z dysku zamiast sieci, bez „wyskakiwania” obrazów.
private final class SharedImageDiskCache: @unchecked Sendable {
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

    func data(for url: URL, variant: CachedImageVariant = .large) -> Data? {
        let path = filePath(for: url, variant: variant)
        guard let data = try? Data(contentsOf: path, options: .mappedIfSafe) else { return nil }
        ioQueue.async { [weak self] in
            try? self?.fileManager.setAttributes([.modificationDate: Date()], ofItemAtPath: path.path)
        }
        return data
    }

    func insert(_ data: Data, for url: URL, variant: CachedImageVariant = .large) {
        let path = filePath(for: url, variant: variant)
        ioQueue.async { [weak self] in
            try? data.write(to: path, options: .atomic)
            self?.pruneIfNeeded()
        }
    }

    private func filePath(for url: URL, variant: CachedImageVariant) -> URL {
        let digest = SHA256.hash(data: Data((url.absoluteString + variant.cacheSuffix).utf8))
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

    private struct Key: Hashable {
        let url: URL
        let variant: CachedImageVariant
    }

    private var inFlight: [Key: Task<UIImage, Error>] = [:]

    func image(for url: URL, variant: CachedImageVariant) async throws -> UIImage {
        if let cached = SharedImageMemoryCache.shared.image(for: url, variant: variant) {
            return cached
        }

        let key = Key(url: url, variant: variant)
        if let task = inFlight[key] {
            return try await task.value
        }

        let task = makeFetchTask(url: url, variant: variant)
        inFlight[key] = task
        defer { inFlight[key] = nil }
        return try await task.value
    }

    func prefetch(_ urls: [URL], variant: CachedImageVariant) {
        for url in urls {
            guard SharedImageMemoryCache.shared.image(for: url, variant: variant) == nil,
                  inFlight[Key(url: url, variant: variant)] == nil else { continue }
            // Reuse ten sam tor co zwykły fetch — defer w image(for:) sprząta inFlight,
            // więc nie ma ryzyka wyścigu z równoległym zapotrzebowaniem na ten sam URL.
            Task { [weak self] in
                _ = try? await self?.image(for: url, variant: variant)
            }
        }
    }

    private func makeFetchTask(url: URL, variant: CachedImageVariant) -> Task<UIImage, Error> {
        let session = self.session
        return Task.detached(priority: .userInitiated) {
            // 1. Gotowa miniatura z dysku: mały JPEG, dekoduje się w 2–3 ms,
            //    więc rozgrzanie całego katalogu mieści się w czasie loadera.
            if variant == .thumbnail,
               let data = SharedImageDiskCache.shared.data(for: url, variant: .thumbnail),
               let decoded = await Self.decode(data: data, variant: variant) {
                SharedImageMemoryCache.shared.insert(decoded, for: url, variant: variant)
                return decoded
            }

            // 2. Oryginał z dysku, 3. z sieci.
            let original: Data
            if let data = SharedImageDiskCache.shared.data(for: url) {
                original = data
            } else {
                let (data, _) = try await session.data(from: url)
                original = data
                SharedImageDiskCache.shared.insert(data, for: url)
            }

            guard let decoded = await Self.decode(data: original, variant: variant) else {
                throw CachedAsyncImageError.invalidImageData
            }
            SharedImageMemoryCache.shared.insert(decoded, for: url, variant: variant)
            if variant == .thumbnail, let jpeg = decoded.jpegData(compressionQuality: 0.85) {
                SharedImageDiskCache.shared.insert(jpeg, for: url, variant: .thumbnail)
            }
            return decoded
        }
    }

    private static func decode(data: Data, variant: CachedImageVariant) async -> UIImage? {
        await ImageDecodeGate.shared.enter()
        let image: UIImage? = {
            guard let source = CGImageSourceCreateWithData(data as CFData, nil) else {
                return UIImage(data: data)
            }
            // Dekodowanie od razu do docelowej wielkości — bez tego SwiftUI
            // dostawał bitmapę 3–5 MP tylko po to, żeby ją pomniejszyć.
            let options: [CFString: Any] = [
                kCGImageSourceCreateThumbnailFromImageAlways: true,
                kCGImageSourceShouldCacheImmediately: true,
                kCGImageSourceCreateThumbnailWithTransform: true,
                kCGImageSourceThumbnailMaxPixelSize: variant.maxPixelSize
            ]
            guard let cg = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary) else {
                return UIImage(data: data)
            }
            return UIImage(cgImage: cg)
        }()
        await ImageDecodeGate.shared.leave()

        guard let image else { return nil }
        // byPreparingForDisplay dekoduje poza main threadem — bez tego pierwszy render
        // obrazu blokuje scroll i wywołuje efekt „wyskakiwania”.
        return await image.byPreparingForDisplay() ?? image
    }
}

/// Warmuje cache obrazów dla przyszłych widoków — wołaj gdy znasz URL-e wcześniej
/// niż pojawią się na ekranie (np. po załadowaniu listy przepisów / stronicowaniu).
enum ImagePrefetcher {
    static func prefetch(_ urls: [URL], variant: CachedImageVariant = .thumbnail) {
        guard !urls.isEmpty else { return }
        Task.detached(priority: .utility) {
            await SharedImagePipeline.shared.prefetch(urls, variant: variant)
        }
    }

    /// Jak `prefetch`, ale czeka aż pierwsza partia miniaturek zostanie zdekodowana
    /// i będzie w cache pamięciowym. Używane przez smart startup loader, żeby
    /// lista przepisów nie „wyskakiwała” okładkami zaraz po wejściu.
    static func prefetchAwaiting(_ urls: [URL], variant: CachedImageVariant = .thumbnail) async {
        guard !urls.isEmpty else { return }
        await withTaskGroup(of: Void.self) { group in
            for url in urls {
                group.addTask(priority: .userInitiated) {
                    _ = try? await SharedImagePipeline.shared.image(for: url, variant: variant)
                }
            }
        }
    }
}

struct CachedAsyncImage<Content: View>: View {
    private let url: URL?
    private let variant: CachedImageVariant
    private let content: (AsyncImagePhase) -> Content

    @State private var phase: AsyncImagePhase

    init(
        url: URL?,
        variant: CachedImageVariant = .thumbnail,
        @ViewBuilder content: @escaping (AsyncImagePhase) -> Content
    ) {
        self.url = url
        self.variant = variant
        self.content = content
        _phase = State(initialValue: Self.initialPhase(for: url, variant: variant))
    }

    var body: some View {
        content(phase)
            // Reset synchroniczny przy zmianie URL (LazyVGrid podmienia content w recyklowanej komórce):
            // bez tego widać na klatkę starą okładkę z poprzedniego recipe.
            .onChange(of: url, initial: false) { _, newURL in
                phase = Self.initialPhase(for: newURL, variant: variant)
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

        if SharedImageMemoryCache.shared.image(for: url, variant: variant) != nil, case .success = phase {
            return
        }

        // Był już obraz (miniatura w roli zastępczej) — duża wersja podmienia
        // go bez animacji: to ten sam kadr, tylko ostrzejszy.
        let hadPlaceholder: Bool = { if case .success = phase { true } else { false } }()

        do {
            let image = try await SharedImagePipeline.shared.image(for: url, variant: variant)
            if hadPlaceholder {
                phase = .success(Image(uiImage: image))
                return
            }
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
            if !hadPlaceholder { phase = .failure(error) }
        }
    }

    private static func initialPhase(for url: URL?, variant: CachedImageVariant) -> AsyncImagePhase {
        guard let url else { return .empty }
        if let image = SharedImageMemoryCache.shared.image(for: url, variant: variant) {
            return .success(Image(uiImage: image))
        }
        // Duże zdjęcie jeszcze niezdekodowane, ale miniatura już jest (lista,
        // z której użytkownik właśnie przyszedł) — pokazujemy ją od pierwszej
        // klatki zamiast pustego tła.
        if variant == .large, let thumb = SharedImageMemoryCache.shared.image(for: url, variant: .thumbnail) {
            return .success(Image(uiImage: thumb))
        }
        return .empty
    }
}
