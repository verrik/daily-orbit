import AppKit
import SwiftUI
import ServiceManagement

@MainActor
final class OrbitModel: ObservableObject {
    @Published var snapshot: OrbitSnapshot?
    @Published var image: NSImage?
    @Published var busy = false
    @Published var status = "Connecting to NASA…"
    @Published var isError = false
    @Published var page = 0
    @Published var autoUpdate: Bool { didSet { defaults.set(autoUpdate, forKey: "autoUpdate") } }
    @Published var fit: WallpaperFit { didSet { defaults.set(fit.rawValue, forKey: "wallpaperFit") } }
    @Published var loginEnabled = false
    @Published var loginNeedsApproval = false
    let store: OrbitStore
    let service: APODService
    let defaults = UserDefaults.standard
    private var timer: Timer?
    private var lastAttempt: Date?
    private var observers = [NSObjectProtocol]()

    init(store: OrbitStore = .standard) {
        self.store = store
        self.service = APODService(store: store)
        autoUpdate = defaults.object(forKey: "autoUpdate") as? Bool ?? true
        fit = WallpaperFit(rawValue: defaults.string(forKey: "wallpaperFit") ?? "") ?? .fill
        snapshot = store.load()
        if let snapshot { image = NSImage(contentsOf: store.imageURL(for: snapshot)); status = "Your saved view of the universe." }
        updateLoginStatus()
    }

    func start() {
        guard timer == nil else { return }
        if autoUpdate, snapshot != nil { apply() }
        Task { await refreshIfDue() }
        timer = Timer.scheduledTimer(withTimeInterval: 900, repeats: true) { [weak self] _ in
            Task { @MainActor in await self?.refreshIfDue() }
        }
        for name in [NSWorkspace.didWakeNotification, NSWorkspace.activeSpaceDidChangeNotification, NSWorkspace.screensDidWakeNotification] {
            observers.append(NSWorkspace.shared.notificationCenter.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                Task { @MainActor in await self?.refreshIfDue() }
            })
        }
        observers.append(NotificationCenter.default.addObserver(forName: NSApplication.didBecomeActiveNotification, object: nil, queue: .main) { [weak self] _ in
            Task { @MainActor in self?.updateLoginStatus() }
        })
    }

    func refreshIfDue() async {
        guard autoUpdate || snapshot == nil else { return }
        guard OrbitDate.shouldRefresh(snapshot), lastAttempt.map({ Date().timeIntervalSince($0) >= 3600 }) ?? true else { return }
        await refresh()
    }

    func refresh() async {
        guard !busy else { return }
        busy = true; isError = false; status = "Finding your next view of the universe…"; lastAttempt = Date()
        defer { busy = false }
        do {
            let next = try await service.refresh()
            snapshot = next
            image = NSImage(contentsOf: store.imageURL(for: next))
            if autoUpdate { try applyWallpaper() }
            else { status = "Picture saved. Ready when you are." }
        } catch {
            isError = true
            status = error.localizedDescription + (snapshot == nil ? "" : " Showing your saved picture.")
        }
    }

    func apply() {
        do { try applyWallpaper() }
        catch { isError = true; status = error.localizedDescription }
    }

    private func applyWallpaper() throws {
        guard let snapshot else { throw OrbitError.message("Download a picture first.") }
        let count = try Desktop.apply(store.imageURL(for: snapshot), fit: fit, store: store)
        isError = false
        status = "Wallpaper set on \(count == 1 ? "your display" : "\(count) displays")." + (snapshot.usesFallback ? " Using the latest still image." : "")
    }

    func restore() {
        do {
            // Pause first so a subsequent check cannot undo a successful restore.
            autoUpdate = false
            try Desktop.restore(store: store)
            isError = false; status = "Previous wallpaper restored. Daily updates are paused."
        } catch { isError = true; status = error.localizedDescription }
    }

    func updateLoginStatus() {
        loginEnabled = SMAppService.mainApp.status == .enabled || SMAppService.mainApp.status == .requiresApproval
        loginNeedsApproval = SMAppService.mainApp.status == .requiresApproval
    }

    func setLogin(_ enabled: Bool) {
        do {
            if enabled && SMAppService.mainApp.status == .notRegistered { try SMAppService.mainApp.register() }
            else if !enabled && SMAppService.mainApp.status != .notRegistered { try SMAppService.mainApp.unregister() }
            updateLoginStatus()
            isError = false
            status = loginNeedsApproval ? "Allow Daily Orbit in System Settings → General → Login Items." : (enabled ? "Daily Orbit will open at login." : "Launch at login is off.")
        } catch {
            updateLoginStatus(); isError = true
            status = "Could not change login settings: \(error.localizedDescription) Move the app to Applications and try again."
        }
    }

    func installSaver() {
        guard let saver = Bundle.main.url(forResource: "Daily Orbit", withExtension: "saver") else {
            isError = true; status = "The screen saver bundle is missing. Rebuild the app."; return
        }
        // macOS presents its own install flow, then lets the user select the screen saver.
        if NSWorkspace.shared.open(saver) {
            isError = false; status = "Follow macOS’s install prompt, then select Daily Orbit in Screen Saver settings."
        } else { isError = true; status = "Could not open the screen saver installer." }
    }

    func showFolder() {
        do { try FileManager.default.createDirectory(at: store.imagesURL, withIntermediateDirectories: true)
            NSWorkspace.shared.open(store.imagesURL)
        } catch { isError = true; status = error.localizedDescription }
    }
}

@MainActor
final class OrbitDelegate: NSObject, NSApplicationDelegate {
    static weak var model: OrbitModel?
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { false }
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        if !flag { showOrbitWindow() }
        return true
    }
    func applicationDidFinishLaunching(_ notification: Notification) {
        Self.model?.start()
        showOrbitWindow()
    }
}

@MainActor
func showOrbitWindow() {
    NSApp.activate(ignoringOtherApps: true)
    NSApp.windows.first(where: { $0.identifier?.rawValue == "orbit" || $0.title == "Daily Orbit" })?.makeKeyAndOrderFront(nil)
}

struct DailyOrbitApp: App {
    @NSApplicationDelegateAdaptor(OrbitDelegate.self) var delegate
    @StateObject private var model = OrbitModel()
    init() {}
    var body: some Scene {
        Window("Daily Orbit", id: "orbit") {
            OrbitWindow(model: model)
                .onAppear { OrbitDelegate.model = model; model.startIfNeeded() }
                .preferredColorScheme(.dark)
        }
        .defaultSize(width: 1080, height: 820)
        .windowStyle(.hiddenTitleBar)
        .commands { CommandGroup(replacing: .newItem) {} }

        MenuBarExtra("Daily Orbit", systemImage: "sparkles") {
            Text(model.snapshot?.image.title.orbitPlainText ?? "Daily Orbit")
            Button("Open Daily Orbit") { showOrbitWindow() }
            Button(model.busy ? "Updating…" : "Refresh from NASA") { Task { await model.refresh() } }.disabled(model.busy)
            Button("Set as wallpaper") { model.apply() }.disabled(model.snapshot == nil || model.busy)
            Toggle("Daily wallpaper updates", isOn: $model.autoUpdate)
            Divider()
            Button("Quit Daily Orbit") { NSApp.terminate(nil) }.keyboardShortcut("q")
        }
    }
}

extension OrbitModel {
    func startIfNeeded() {
        if !defaults.bool(forKey: "hasLaunched") { defaults.set(true, forKey: "hasLaunched") }
        // The window and app delegate can arrive in either order; start is idempotent.
        if timer == nil { start() }
    }
}

private let orbitAccent = Color(red: 0.64, green: 0.79, blue: 1)
private let orbitMuted = Color(red: 0.56, green: 0.62, blue: 0.72)

struct OrbitWindow: View {
    @ObservedObject var model: OrbitModel
    var body: some View {
        HStack(spacing: 0) {
            sidebar.frame(width: 206)
            Rectangle().fill(Color.white.opacity(0.07)).frame(width: 1)
            VStack(alignment: .leading, spacing: 0) {
                ScrollView {
                    VStack(alignment: .leading, spacing: 22) {
                        if model.page == 0 { today } else { preferences }
                    }.padding(30)
                }.id(model.page)
                statusBar
            }
        }
        .frame(minWidth: 980, minHeight: 760)
        .background(Color(red: 0.035, green: 0.055, blue: 0.095))
        .tint(orbitAccent)
    }

    var sidebar: some View {
        VStack(alignment: .leading, spacing: 28) {
            HStack(spacing: 10) {
                Image(systemName: "sparkles").font(.system(size: 26, weight: .light)).foregroundStyle(orbitAccent)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Daily Orbit").font(.system(size: 18, weight: .semibold))
                    Text("A NEW PERSPECTIVE").font(.system(size: 8, weight: .medium, design: .monospaced)).tracking(1.3).foregroundStyle(orbitMuted)
                }
            }.padding(.top, 38).padding(.bottom, 12)
            VStack(spacing: 6) {
                nav("Today’s picture", icon: "photo", page: 0)
                nav("Preferences", icon: "slider.horizontal.3", page: 1)
            }
            Spacer()
            VStack(alignment: .leading, spacing: 12) {
                Text("A small daily reminder\nof a very big universe.").font(.system(size: 14)).lineSpacing(5).foregroundStyle(orbitMuted)
                Rectangle().fill(Color.white.opacity(0.08)).frame(height: 1)
                Label("NASA APOD", systemImage: "arrow.up.right").font(.system(size: 11, weight: .medium)).foregroundStyle(orbitMuted)
                    .onTapGesture { NSWorkspace.shared.open(URL(string: "https://science.nasa.gov/astronomy/astronomy-picture-of-the-day/")!) }
                HStack(spacing: 6) {
                    Circle().fill(model.autoUpdate ? Color.green.opacity(0.8) : .orange).frame(width: 5, height: 5)
                    Text(model.autoUpdate ? "Daily updates on" : "Daily updates paused").font(.system(size: 11)).foregroundStyle(orbitMuted)
                }
            }.padding(.bottom, 20)
        }.padding(.horizontal, 20).background(Color.white.opacity(0.015))
    }

    func nav(_ text: String, icon: String, page: Int) -> some View {
        Button { model.page = page } label: {
            HStack(spacing: 11) {
                Image(systemName: icon).frame(width: 17)
                Text(text).font(.system(size: 13, weight: .medium))
                Spacer(minLength: 0)
            }.padding(.horizontal, 12).padding(.vertical, 12)
                .foregroundStyle(model.page == page ? orbitAccent : orbitMuted)
                .background(model.page == page ? orbitAccent.opacity(0.11) : .clear, in: RoundedRectangle(cornerRadius: 9))
        }.buttonStyle(.plain)
    }

    var today: some View {
        Group {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 8) {
                    Text("ASTRONOMY PICTURE OF THE DAY").font(.system(size: 10, weight: .medium, design: .monospaced)).tracking(1.8).foregroundStyle(orbitAccent)
                    Text("Your daily dose of space.").font(.system(size: 29, weight: .medium))
                }
                Spacer()
                Button { Task { await model.refresh() } } label: {
                    if model.busy { ProgressView().controlSize(.small).frame(width: 18, height: 18) }
                    else { Image(systemName: "arrow.clockwise").font(.system(size: 15)).frame(width: 18, height: 18) }
                }.buttonStyle(.plain).padding(11).background(.white.opacity(0.06), in: Circle()).disabled(model.busy).help("Refresh from NASA")
            }
            ZStack(alignment: .bottomLeading) {
                if let image = model.image {
                    GeometryReader { bounds in
                        Image(nsImage: image).resizable().scaledToFill().frame(width: bounds.size.width, height: bounds.size.height).clipped()
                    }
                    LinearGradient(colors: [.clear, .black.opacity(0.55)], startPoint: .center, endPoint: .bottom)
                    HStack {
                        Label(model.snapshot?.usesFallback == true ? "LATEST STILL IMAGE" : "TODAY’S PICTURE", systemImage: "sparkle")
                            .font(.system(size: 9, weight: .semibold, design: .monospaced)).tracking(1.2)
                        Spacer()
                        Text(model.snapshot?.image.date ?? "").font(.system(size: 11, design: .monospaced))
                    }.padding(20).foregroundStyle(.white)
                } else {
                    Color.white.opacity(0.025)
                    VStack(spacing: 14) {
                        Image(systemName: "sparkles").font(.system(size: 46, weight: .ultraLight)).foregroundStyle(orbitAccent)
                        Text(model.busy ? "A universe worth waiting for." : "Your next view is out there.").foregroundStyle(orbitMuted)
                        if !model.busy { Button("Try again") { Task { await model.refresh() } } }
                    }.frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            }.frame(height: 340).clipShape(RoundedRectangle(cornerRadius: 16))
            VStack(alignment: .leading, spacing: 14) {
                HStack(alignment: .top, spacing: 20) {
                    VStack(alignment: .leading, spacing: 6) {
                        Text(model.snapshot?.image.title.orbitPlainText ?? "Connecting to the cosmos").font(.system(size: 23, weight: .medium)).fixedSize(horizontal: false, vertical: true)
                        if let snapshot = model.snapshot {
                            Text((snapshot.image.credit ?? snapshot.image.copyright ?? "NASA APOD").orbitPlainText)
                                .font(.system(size: 10)).foregroundStyle(orbitMuted).lineLimit(2)
                        }
                    }
                    Spacer(minLength: 0)
                    Button { model.apply() } label: {
                        Label("Set wallpaper", systemImage: "desktopcomputer").font(.system(size: 12, weight: .semibold)).padding(.vertical, 5)
                    }.buttonStyle(.borderedProminent).controlSize(.large).disabled(model.snapshot == nil || model.busy)
                }
                if let snapshot = model.snapshot {
                    Text(snapshot.image.explanation.orbitPlainText).font(.system(size: 13)).lineSpacing(4).foregroundStyle(orbitMuted).lineLimit(3)
                    HStack {
                        if let url = snapshot.image.storyURL { Link("Read the story on NASA ↗", destination: url).font(.system(size: 11, weight: .medium)) }
                        Spacer()
                        if snapshot.usesFallback { Text("Today’s APOD is \(snapshot.latest.mediaType). Showing \(snapshot.image.date).").font(.system(size: 10)).foregroundStyle(orbitMuted) }
                    }
                }
            }
            HStack(spacing: 12) {
                miniCard("A new view, every day", subtitle: "Updates while Daily Orbit is running.", icon: "sun.max") {
                    Toggle("Daily updates", isOn: $model.autoUpdate).labelsHidden().toggleStyle(.switch).controlSize(.small)
                        .onChange(of: model.autoUpdate) { enabled in if enabled { Task { await model.refresh() } } }
                }
                miniCard("Space, on pause", subtitle: "Use your APOD as a screen saver.", icon: "moon.stars") {
                    Button("Set up") { model.installSaver() }.controlSize(.small)
                }
            }
        }
    }

    func miniCard<Content: View>(_ title: String, subtitle: String, icon: String, @ViewBuilder action: () -> Content) -> some View {
        HStack(spacing: 12) {
            Image(systemName: icon).font(.system(size: 19, weight: .light)).foregroundStyle(orbitAccent)
            VStack(alignment: .leading, spacing: 5) {
                Text(title).font(.system(size: 12, weight: .medium))
                Text(subtitle).font(.system(size: 10)).foregroundStyle(orbitMuted)
            }
            Spacer(minLength: 4)
            action()
        }.padding(16).frame(maxWidth: .infinity).background(.white.opacity(0.035), in: RoundedRectangle(cornerRadius: 12))
    }

    var preferences: some View {
        VStack(alignment: .leading, spacing: 24) {
            Text("MAKE IT YOURS").font(.system(size: 10, design: .monospaced)).tracking(1.8).foregroundStyle(orbitAccent)
            Text("A little space in your routine.").font(.system(size: 29, weight: .medium))
            VStack(alignment: .leading, spacing: 22) {
                setting("Daily wallpaper", detail: "Check NASA hourly until today’s APOD is published. Keep the menu bar app running.") {
                    Toggle("Daily wallpaper", isOn: $model.autoUpdate).labelsHidden().toggleStyle(.switch)
                        .onChange(of: model.autoUpdate) { enabled in if enabled { Task { await model.refresh() } } }
                }
                Divider()
                setting("Launch at login", detail: "Start Daily Orbit when you sign in to your Mac.") {
                    Toggle("Launch at login", isOn: Binding(get: { model.loginEnabled }, set: { model.setLogin($0) })).labelsHidden().toggleStyle(.switch)
                }
                if model.loginNeedsApproval { Button("Allow in System Settings") { SMAppService.openSystemSettingsLoginItems() } }
                Divider()
                setting("Wallpaper layout", detail: "Fill crops the edges. Fit keeps the whole picture with black borders.") {
                    Picker("Layout", selection: $model.fit) { ForEach(WallpaperFit.allCases, id: \.self) { Text($0.rawValue).tag($0) } }.labelsHidden().frame(width: 145)
                }
                Button("Apply layout to wallpaper") { model.apply() }.disabled(model.snapshot == nil)
            }.padding(22).background(.white.opacity(0.035), in: RoundedRectangle(cornerRadius: 14))
            VStack(alignment: .leading, spacing: 14) {
                Label("The screen saver", systemImage: "moon.stars").font(.system(size: 17, weight: .medium))
                Text("Install the included screen saver, then select Daily Orbit in macOS Screen Saver settings. It gently pans across the latest saved image, even when you’re offline. Daily Orbit refreshes the image while the app is running.")
                    .font(.system(size: 13)).lineSpacing(4).foregroundStyle(orbitMuted)
                HStack {
                    Button("Install screen saver…") { model.installSaver() }
                    Button("Screen Saver settings") { NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.ScreenSaver-Settings.extension")!) }
                }
            }.padding(22).frame(maxWidth: .infinity, alignment: .leading).background(.white.opacity(0.035), in: RoundedRectangle(cornerRadius: 14))
            HStack {
                Button("Open saved pictures") { model.showFolder() }
                Spacer()
                Button("Restore previous wallpaper") { model.restore() }.disabled(model.busy)
            }
            Text("Images and settings stay on this Mac. NASA supplies the pictures and credits; no API key or account is needed. Closing this window keeps Daily Orbit in the menu bar. Quit from the menu bar to stop updates.")
                .font(.system(size: 11)).lineSpacing(4).foregroundStyle(orbitMuted)
        }
    }

    func setting<Content: View>(_ title: String, detail: String, @ViewBuilder control: () -> Content) -> some View {
        HStack(spacing: 25) {
            VStack(alignment: .leading, spacing: 7) {
                Text(title).font(.system(size: 14, weight: .medium))
                Text(detail).font(.system(size: 12)).foregroundStyle(orbitMuted).fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 5)
            control()
        }
    }

    var statusBar: some View {
        HStack(spacing: 8) {
            Image(systemName: model.isError ? "exclamationmark.circle" : (model.busy ? "arrow.down.circle" : "checkmark.circle"))
                .foregroundStyle(model.isError ? Color.orange : orbitAccent)
            Text(model.status).font(.system(size: 11)).foregroundStyle(model.isError ? .orange : orbitMuted).lineLimit(3)
            Spacer(minLength: 0)
        }.padding(.horizontal, 30).padding(.vertical, 14).frame(minHeight: 46)
            .background(Color.white.opacity(0.025))
    }
}

#if !ORBIT_PREVIEW
@main
struct DailyOrbitMain {
    @MainActor static func main() {
        let args = CommandLine.arguments
        if args.contains("--sync-once") {
            let app = NSApplication.shared
            app.setActivationPolicy(.accessory)
            app.finishLaunching()
            let store: OrbitStore
            if let index = args.firstIndex(of: "--storage"), args.indices.contains(index + 1) {
                store = OrbitStore(root: URL(fileURLWithPath: args[index + 1], isDirectory: true))
            } else { store = .standard }
            Task { @MainActor in
                do {
                    let result = try await APODService(store: store).refresh()
                    print("NASA APOD: \(result.latest.date) — \(result.latest.title.orbitPlainText)")
                    print("Saved image: \(store.imageURL(for: result).path)")
                    if args.contains("--apply") {
                        let count = try Desktop.apply(store.imageURL(for: result), fit: .fill, store: store)
                        // macOS commits the desktop update asynchronously. Keep the
                        // event loop alive before checking the result or exiting.
                        try await Task.sleep(nanoseconds: 2_000_000_000)
                        print("Wallpaper applied to \(count) display(s).")
                        var verified = true
                        for screen in NSScreen.screens {
                            let matches = NSWorkspace.shared.desktopImageURL(for: screen)?.standardizedFileURL == store.imageURL(for: result).standardizedFileURL
                            verified = verified && matches
                            print("Verified display \(Desktop.displayID(screen)): \(matches ? "matches APOD" : "system reports a different wallpaper")")
                        }
                        if !verified { throw OrbitError.message("macOS did not confirm the wallpaper change. Open Daily Orbit and choose Set wallpaper.") }
                    }
                    exit(0)
                } catch { fputs("Daily Orbit: \(error.localizedDescription)\n", stderr); exit(1) }
            }
            app.run()
        } else {
            DailyOrbitApp.main()
        }
    }
}
#endif
