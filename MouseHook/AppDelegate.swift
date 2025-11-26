//
//  AppDelegate.swift
//  MouseHook
//
//  Created by Johnson, Brad on 2023-01-01.
//

import Cocoa
import Combine

class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate {
    private var statusItem: NSStatusItem!
    private var menu: NSMenu!
    private var mouseWindow: NSWindow!
    private var mouseController: MouseViewController!
    private var slowEventThrottle: Publishers.Throttle<PassthroughSubject<NSEvent, Never>, DispatchQueue>!
    private var fastEventThrottle: Publishers.Throttle<PassthroughSubject<NSEvent, Never>, DispatchQueue>!
    private var refreshObserver: NSKeyValueObservation!
    private var eventMonitor: Any!
    private var cancellationToken: AnyCancellable?
    private let eventQueue = DispatchQueue(label: "com.mousehook.events", qos: .userInteractive)
    
    @objc private dynamic var fastFreqRefresh: Bool = false
    
    private let eventSubject = PassthroughSubject<NSEvent, Never>()
    private let userDefaults = UserDefaults.standard
    
    deinit {
        refreshObserver?.invalidate()
        NSEvent.removeMonitor(eventMonitor!)
    }

    func applicationDidFinishLaunching(_ aNotification: Notification) {
        NSApp.setActivationPolicy(.accessory) // hide Dock icon; status item only
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        if let button = statusItem.button {
            button.image = NSImage(named: NSImage.Name("mousehook-menubar"))
        }
        mouseController = MouseViewController()
        fastEventThrottle = self.eventSubject.throttle(for: fastRefreshStride(), scheduler: eventQueue, latest: true)
        slowEventThrottle = self.eventSubject.throttle(for: .seconds(1.0/5.0), scheduler: eventQueue, latest: true) // 5Hz
        
        setupMouseWindow()
        setupMenu()
        statusItem.menu = menu
        
        refreshObserver = self.observe(\.fastFreqRefresh, options: [.new], changeHandler: { (this, change) in
            self.cancellationToken?.cancel()
            
            let eventThrottle = change.newValue! ? self.fastEventThrottle : self.slowEventThrottle
            
            self.cancellationToken = eventThrottle?
                .receive(on: DispatchQueue.main)
                .sink(receiveValue: { [weak self] event in
                    // Don't bother updating mouse position if it is currently hidden
                    self?.update(event)
                })
        })
        fastFreqRefresh = true
        
        //TODO: Find a way to make global event monitoring not take up SO MUCH CPU
        eventMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.mouseMoved, .leftMouseDragged, .rightMouseDragged, .otherMouseDragged]) { (event) in
            self.eventSubject.send(event)
        }
    }
    
    func update(_ event: NSEvent) {
        let cursorVisible = mouseController.update(event)
        
        if cursorVisible {
            let mousePosition = NSEvent.mouseLocation
            mouseWindow.setFrameOrigin(mouseController.getFrameOrigin(mousePosition))
        }
        // Only use fast refresh rate if the cursor is actually visible
        if (fastFreqRefresh != cursorVisible) {
            fastFreqRefresh = cursorVisible
        }
    }
    
    func setupMouseWindow() {
        mouseWindow = NSWindow(contentViewController: mouseController)
        mouseWindow.styleMask = [.borderless]
        mouseWindow.ignoresMouseEvents = true
        let initialSize = mouseController.currentCursorSize == .zero ? NSSize(width: 50, height: 50) : mouseController.currentCursorSize
        mouseWindow.setFrame(NSRect(origin: .zero, size: initialSize), display: false)
        mouseWindow.hasShadow = false
        mouseWindow.backgroundColor = .clear
        mouseWindow.level = .screenSaver
        mouseWindow.orderFront(nil)
        mouseWindow.collectionBehavior = .canJoinAllSpaces
    }
    
    func setupMenu() {
        menu = NSMenu(title: "Status Bar Menu")
        menu.delegate = self
        
        var menuItem = NSMenuItem.separator()
        menuItem.tag=100
        
        menu.addItem(menuItem)
        
        menuItem = NSMenuItem(title: "Quit", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        menuItem.tag=100
        
        menu.addItem(menuItem)
    }
    
    @objc func menuNeedsUpdate(_ menu: NSMenu) {
        menu.items.forEach({
            if ($0.tag != 100) {
                menu.removeItem($0)
            }
        })
        
        var i = 0
        
        NSScreen
            .screens
            .reduce(into: [CGDirectDisplayID: String]()) { $0[$1.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as! CGDirectDisplayID] = $1.localizedName }
            .sorted(by: { $0.0 < $1.0 })
            .forEach {
                let enabled = userDefaults.activeMonitors?.contains($0.key) == true
                let menuItem = NSMenuItem(title: enabled ? "✅\($0.value)" : "❌\($0.value)", action: #selector(menuItemClicked(item:)), keyEquivalent: String(i+1))
                menuItem.identifier = NSUserInterfaceItemIdentifier(String($0.key))
                menuItem.isEnabled = enabled
                menu.insertItem(menuItem, at: i)
                i += 1
            }
    }
    
    @objc func menuItemClicked(item: NSMenuItem) {
        updateEnabledMonitors(CGDirectDisplayID(item.identifier!.rawValue)!)
        mouseController.resetCurrentMonitor()
    }
    
    func updateEnabledMonitors(_ toUpdate: CGDirectDisplayID) {
        var enabledMonitors: [CGDirectDisplayID]
        
        if let actual = userDefaults.activeMonitors as [CGDirectDisplayID]? {
            enabledMonitors = actual
        } else {
            enabledMonitors = [UInt32]()
        }
        
        if let i = enabledMonitors.firstIndex(of: toUpdate) as Int? {
            enabledMonitors.remove(at: i)
        } else {
            enabledMonitors.insert(toUpdate, at: 0)
        }
        
        userDefaults.setActiveMonitors(enabledMonitors)
    }

    private func fastRefreshStride() -> DispatchQueue.SchedulerTimeType.Stride {
        let targetFPS = NSScreen.screens
            .compactMap { $0.maximumFramesPerSecond }
            .filter { $0 > 0 }
            .max() ?? 60
        return .seconds(1.0 / Double(targetFPS))
    }

}

extension UserDefaults {
    @objc dynamic var activeMonitors: [CGDirectDisplayID]? {
        return array(forKey: "enabledMonitors") as? [CGDirectDisplayID]
    }
    
    
    @objc func setActiveMonitors(_ enabledMonitors: [CGDirectDisplayID]) {
        set(enabledMonitors, forKey: "enabledMonitors")
    }
}
