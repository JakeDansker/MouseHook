//
//  ViewController.swift
//  MouseHook
//
//  Created by Johnson, Brad on 2023-01-01.
//

import Cocoa

class MouseViewController: NSViewController {
    private var cursorImageView: NSImageView!
    private var enabledMonitorObserver: NSKeyValueObservation!
    private var cursorObserver: NSKeyValueObservation!
    private var enabledMonitors: Set<CGDirectDisplayID> = Set<CGDirectDisplayID>()
    private var currentMonitor: NSScreen?
    
    @objc private dynamic var currentCursor: NSCursor = NSCursor.current
    
    var currentCursorSize: NSSize { currentCursor.image.size }
    
    override init(nibName nibNameOrNil: NSNib.Name?, bundle nibBundleOrNil: Bundle?) {
        super.init(nibName: nibNameOrNil, bundle: nibBundleOrNil)
        setupMouseViewController()
    }
    
    required init?(coder: NSCoder) {
        super.init(coder: coder)
        setupMouseViewController()
    }
    
    deinit {
        enabledMonitorObserver?.invalidate()
        cursorObserver?.invalidate()
    }
    
    private func setupMouseViewController() {
        cursorImageView = NSImageView()
        cursorImageView.wantsLayer = true
        cursorImageView.image = currentCursor.image
        cursorImageView.imageScaling = .scaleNone
        cursorImageView.layer?.backgroundColor = NSColor.clear.cgColor
        cursorImageView.frame = NSRect(origin: .zero, size: currentCursor.image.size)
        self.view = cursorImageView
        
        setupObservers()
    }
    
    private func setupObservers() {
        enabledMonitorObserver = UserDefaults.standard.observe(\.activeMonitors, options: [.initial, .new], changeHandler: { (defaults, change) in
            if let mons = defaults.activeMonitors as [CGDirectDisplayID]? {
                self.enabledMonitors = Set(mons.map { $0 })
            }
        })
        cursorObserver = self.observe(\.currentCursor, options: [.initial, .new], changeHandler: { (this, change) in
            self.applyCurrentCursorImage()
        })
    }
    
    func getFrameOrigin(_ pt: NSPoint) -> NSPoint {
        let hotSpot = adjustedHotSpot()
        return NSPoint(x: pt.x - hotSpot.x, y: pt.y - hotSpot.y)
    }
    
    
    override func viewDidLoad() {
        let aCursor = NSCursor.resizeUpDown
        view.addCursorRect(view.bounds, cursor: aCursor)
        aCursor.set()
        view.addTrackingRect(view.bounds, owner: aCursor, userData: nil, assumeInside: true)
        
    }
    
    func resetCurrentMonitor(_ mousePosition: NSPoint? = nil) {
        if (mousePosition != nil) {
            currentMonitor = NSScreen.screens.first(where: { $0.frame.contains(mousePosition!) })
        }
        cursorImageView.isHidden = !enabledMonitors.contains(currentMonitor?.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? CGDirectDisplayID ?? kCGNullDirectDisplay)
    }
    
    func update(_ event: NSEvent) -> Bool {
        if let systemCursor = NSCursor.currentSystem, systemCursor !== currentCursor {
            currentCursor = systemCursor
        }
        
        let mousePosition = NSEvent.mouseLocation
        if (currentMonitor?.frame.contains(mousePosition) != true) {
            resetCurrentMonitor(mousePosition)
        }
        
        return !cursorImageView.isHidden
    }
    
    private func applyCurrentCursorImage() {
        let size = currentCursor.image.size
        cursorImageView.image = currentCursor.image
        cursorImageView.frame = NSRect(origin: .zero, size: size)
        view.window?.setContentSize(size)
        cursorImageView.layer?.contentsScale = currentMonitor?.backingScaleFactor ?? NSScreen.main?.backingScaleFactor ?? 1.0
    }
    
    private func adjustedHotSpot() -> NSPoint {
        var spot = currentCursor.hotSpot
        if isArrowCursor() {
            // Arrow hotspot appears to be measured from the top in recent macOS builds.
            // Flip to a bottom-origin measurement so the overlay aligns with the system arrow tip.
            spot = NSPoint(x: spot.x, y: currentCursor.image.size.height - spot.y)
        }
        return spot
    }
    
    private func isArrowCursor() -> Bool {
        let arrow = NSCursor.arrow
        return currentCursor.image.size == arrow.image.size && currentCursor.hotSpot == arrow.hotSpot
    }
}
