import Foundation
import AppKit
import Metal
import ScreenSaver

enum FlowDirection: Int, CaseIterable {
    case down = 0
    case up = 1
    case bothDirections = 2

    var title: String {
        switch self {
        case .down:
            return "Down"
        case .up:
            return "Up"
        case .bothDirections:
            return "Both Directions"
        }
    }
}

enum BidirectionalLayout: Int, CaseIterable {
    case screenHalves = 0
    case alternatingColumns = 1

    var title: String {
        switch self {
        case .screenHalves:
            return "Screen Halves"
        case .alternatingColumns:
            return "Alternating Columns"
        }
    }
}

final class GlyphyxConfig {

    static let defaultCharacterSet = "ABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789!@#$%^&*()[]{}<>?/\\|=+-"
    private static let registeredDefaults: [String: Any] = [
        "fontName": "Menlo-Bold",
        "fontSize": 14.0,
        "fallSpeedMultiplier": 1.0,
        "cameraSpeedMultiplier": 1.0,
        "characterBlur": 0.0,
        "is3D": false,
        "characterSet": defaultCharacterSet,
        "flowDirection": FlowDirection.down.rawValue,
        "bidirectionalLayout": BidirectionalLayout.screenHalves.rawValue,
    ]

    private let defaults: UserDefaults

    init() {
        let bundleID = Bundle(for: GlyphyxConfig.self).bundleIdentifier ?? "com.thiaramus.Glyphyx"
        defaults = ScreenSaverDefaults(forModuleWithName: bundleID) ?? .standard
        defaults.register(defaults: Self.registeredDefaults)
        load()
    }

    // MARK: - Configurable Properties

    var fontName:              String  = "Menlo-Bold"
    var fontSize:              Float   = 14.0
    var foregroundColor:       NSColor = .white
    var glowColor:             NSColor = NSColor(red: 0.5, green: 0.8, blue: 1.0, alpha: 0.5)
    var backgroundColor:       NSColor = .black
    var fallSpeedMultiplier:   Float   = 1.0
    var cameraSpeedMultiplier: Float   = 1.0
    var characterBlur:         Float   = 0.0
    var is3D:                  Bool    = false
    var characterSet:          String  = defaultCharacterSet
    var flowDirection:         FlowDirection = .down
    var bidirectionalLayout:   BidirectionalLayout = .screenHalves

    // MARK: - Metal Helpers

    var foregroundColorSIMD: SIMD4<Float> {
        simd4(from: foregroundColor)
    }

    var trailColorSIMD: SIMD4<Float> {
        // Trail is a dimmer version of the foreground color
        let fg = simd4(from: foregroundColor)
        return SIMD4(fg.x * 0.55, fg.y * 0.55, fg.z * 0.55, fg.w)
    }

    var glowColorSIMD: SIMD4<Float> {
        simd4(from: glowColor)
    }

    var backgroundClearColor: MTLClearColor {
        let (r, g, b, a) = cgFloats(of: backgroundColor)
        return MTLClearColor(red: Double(r), green: Double(g), blue: Double(b), alpha: Double(a))
    }

    private func simd4(from color: NSColor) -> SIMD4<Float> {
        let (r, g, b, a) = cgFloats(of: color)
        return SIMD4(Float(r), Float(g), Float(b), Float(a))
    }

    private func cgFloats(of color: NSColor) -> (CGFloat, CGFloat, CGFloat, CGFloat) {
        var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        let srgb = color.usingColorSpace(.sRGB) ?? color
        srgb.getRed(&r, green: &g, blue: &b, alpha: &a)
        return (r, g, b, a)
    }

    // MARK: - Persistence

    func load() {
        if let v = defaults.string(forKey: "fontName")         { fontName = v }
        if defaults.object(forKey: "fontSize") != nil          { fontSize = defaults.float(forKey: "fontSize") }
        if let d = defaults.data(forKey: "foregroundColor"),
           let c = try? NSKeyedUnarchiver.unarchivedObject(ofClass: NSColor.self, from: d) {
            foregroundColor = c
        }
        if let d = defaults.data(forKey: "glowColor"),
           let c = try? NSKeyedUnarchiver.unarchivedObject(ofClass: NSColor.self, from: d) {
            glowColor = c
        }
        if let d = defaults.data(forKey: "backgroundColor"),
           let c = try? NSKeyedUnarchiver.unarchivedObject(ofClass: NSColor.self, from: d) {
            backgroundColor = c
        }
        if defaults.object(forKey: "fallSpeedMultiplier") != nil {
            fallSpeedMultiplier = defaults.float(forKey: "fallSpeedMultiplier")
        }
        if defaults.object(forKey: "cameraSpeedMultiplier") != nil {
            cameraSpeedMultiplier = defaults.float(forKey: "cameraSpeedMultiplier")
        }
        if defaults.object(forKey: "characterBlur") != nil {
            characterBlur = defaults.float(forKey: "characterBlur")
        }
        if defaults.object(forKey: "is3D") != nil {
            is3D = defaults.bool(forKey: "is3D")
        }
        if let v = defaults.string(forKey: "characterSet"), !v.isEmpty { characterSet = v }
        let flowDirectionRawValue = defaults.integer(forKey: "flowDirection")
        flowDirection = FlowDirection(rawValue: flowDirectionRawValue) ?? .down
        let bidirectionalLayoutRawValue = defaults.integer(forKey: "bidirectionalLayout")
        bidirectionalLayout = BidirectionalLayout(rawValue: bidirectionalLayoutRawValue) ?? .screenHalves
    }

    func save() {
        defaults.set(fontName, forKey: "fontName")
        defaults.set(fontSize, forKey: "fontSize")
        if let d = try? NSKeyedArchiver.archivedData(withRootObject: foregroundColor, requiringSecureCoding: false) {
            defaults.set(d, forKey: "foregroundColor")
        }
        if let d = try? NSKeyedArchiver.archivedData(withRootObject: glowColor, requiringSecureCoding: false) {
            defaults.set(d, forKey: "glowColor")
        }
        if let d = try? NSKeyedArchiver.archivedData(withRootObject: backgroundColor, requiringSecureCoding: false) {
            defaults.set(d, forKey: "backgroundColor")
        }
        defaults.set(fallSpeedMultiplier,   forKey: "fallSpeedMultiplier")
        defaults.set(cameraSpeedMultiplier, forKey: "cameraSpeedMultiplier")
        defaults.set(characterBlur,         forKey: "characterBlur")
        defaults.set(is3D,                  forKey: "is3D")
        defaults.set(characterSet,          forKey: "characterSet")
        defaults.set(flowDirection.rawValue, forKey: "flowDirection")
        defaults.set(bidirectionalLayout.rawValue, forKey: "bidirectionalLayout")
        defaults.synchronize()
    }
}
