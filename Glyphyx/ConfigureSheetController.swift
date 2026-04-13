import AppKit
import ScreenSaver

final class ConfigureSheetController: NSWindowController {

    private let config: GlyphyxConfig
    private let onDismiss: () -> Void

    // Controls
    private var fontPopUp:          NSPopUpButton!
    private var fontSizeField:      NSTextField!
    private var fontSizeStepper:    NSStepper!
    private var foregroundWell:     NSColorWell!
    private var glowWell:           NSColorWell!
    private var backgroundWell:     NSColorWell!
    private var fallSpeedSlider:    NSSlider!
    private var fallSpeedLabel:     NSTextField!
    private var cameraSpeedSlider:  NSSlider!
    private var cameraSpeedLabel:   NSTextField!
    private var is3DCheckbox:       NSButton!
    private var characterSetField:  NSTextField!

    init(config: GlyphyxConfig, onDismiss: @escaping () -> Void) {
        self.config = config
        self.onDismiss = onDismiss

        let w = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 460, height: 490),
            styleMask:   [.titled],
            backing:     .buffered,
            defer:       false
        )
        w.title = "Glyphyx Settings"
        w.isReleasedWhenClosed = false

        super.init(window: w)
        buildUI()
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) not supported") }

    // MARK: - UI Construction

    private func buildUI() {
        guard let content = window?.contentView else { return }

        // --- Font family ---
        fontPopUp = NSPopUpButton()
        let monospaceFamilies: [String] = {
            let all = NSFontManager.shared.availableFontFamilies
            let known = ["Menlo", "Courier", "Courier New", "Monaco", "PT Mono",
                         "SF Mono", "Source Code Pro", "Fira Code", "JetBrains Mono",
                         "Hack", "Inconsolata", "IBM Plex Mono", "Roboto Mono",
                         "Cascadia Code", "Anonymous Pro"]
            var result = all.filter { name in
                name.lowercased().contains("mono") ||
                name.lowercased().contains("code") ||
                name.lowercased().contains("courier") ||
                known.contains(name)
            }
            // Always include current font's family
            if let family = NSFont(name: config.fontName, size: 12)?.familyName,
               !result.contains(family) {
                result.append(family)
            }
            return result.sorted()
        }()
        monospaceFamilies.forEach { fontPopUp.addItem(withTitle: $0) }
        let currentFamily = NSFont(name: config.fontName, size: 12)?.familyName ?? "Menlo"
        fontPopUp.selectItem(withTitle: currentFamily)

        // --- Font size ---
        fontSizeField = NSTextField()
        fontSizeField.stringValue = String(Int(config.fontSize))
        fontSizeField.widthAnchor.constraint(equalToConstant: 44).isActive = true
        fontSizeStepper = NSStepper()
        fontSizeStepper.minValue = 8; fontSizeStepper.maxValue = 72; fontSizeStepper.increment = 1
        fontSizeStepper.intValue = Int32(config.fontSize)
        fontSizeStepper.target = self; fontSizeStepper.action = #selector(stepperChanged(_:))
        fontSizeField.target = self; fontSizeField.action = #selector(fontSizeFieldChanged(_:))
        let fontSizeRow = hStack([fontSizeField, fontSizeStepper], spacing: 2)

        // --- Color wells ---
        foregroundWell = colorWell(color: config.foregroundColor)
        glowWell       = colorWell(color: config.glowColor)
        backgroundWell = colorWell(color: config.backgroundColor)

        // --- Fall speed ---
        fallSpeedSlider = slider(min: 0.25, max: 4.0, value: config.fallSpeedMultiplier)
        fallSpeedLabel  = valueLabel(for: config.fallSpeedMultiplier, format: "%.2f×")
        fallSpeedSlider.target = self; fallSpeedSlider.action = #selector(fallSpeedChanged(_:))
        let fallSpeedRow = hStack([fallSpeedSlider, fallSpeedLabel], spacing: 6)

        // --- Camera speed ---
        cameraSpeedSlider = slider(min: 0.0, max: 3.0, value: config.cameraSpeedMultiplier)
        cameraSpeedLabel  = valueLabel(for: config.cameraSpeedMultiplier, format: "%.2f×")
        cameraSpeedSlider.target = self; cameraSpeedSlider.action = #selector(cameraSpeedChanged(_:))
        let cameraSpeedRow = hStack([cameraSpeedSlider, cameraSpeedLabel], spacing: 6)

        // --- 3D toggle ---
        is3DCheckbox = NSButton(checkboxWithTitle: "Enable 3D mode", target: nil, action: nil)
        is3DCheckbox.state = config.is3D ? .on : .off

        // --- Character set ---
        characterSetField = NSTextField()
        characterSetField.stringValue    = config.characterSet
        characterSetField.placeholderString = "Characters used in the animation"
        characterSetField.font = NSFont.monospacedSystemFont(ofSize: 11, weight: .regular)

        // --- Assemble rows ---
        let rows: [(String, NSView)] = [
            ("Font",              fontPopUp),
            ("Font Size",         fontSizeRow),
            ("Foreground Color",  foregroundWell),
            ("Glow Color",        glowWell),
            ("Background Color",  backgroundWell),
            ("Fall Speed",        fallSpeedRow),
            ("Camera Speed",      cameraSpeedRow),
            ("Animation Mode",    is3DCheckbox),
            ("Character Set",     characterSetField),
        ]

        let grid = buildGrid(rows: rows)

        // --- Buttons ---
        let cancelBtn = NSButton(title: "Cancel", target: self, action: #selector(cancel(_:)))
        cancelBtn.bezelStyle = .rounded
        let okBtn = NSButton(title: "OK", target: self, action: #selector(ok(_:)))
        okBtn.bezelStyle = .rounded
        okBtn.keyEquivalent = "\r"

        let spacer = NSView()
        spacer.setContentHuggingPriority(.defaultLow, for: .horizontal)
        let buttonRow = hStack([spacer, cancelBtn, okBtn], spacing: 8)

        // --- Outer stack ---
        let outer = NSStackView(views: [grid, buttonRow])
        outer.orientation = .vertical
        outer.spacing = 16
        outer.alignment = .leading

        outer.translatesAutoresizingMaskIntoConstraints = false
        content.addSubview(outer)
        NSLayoutConstraint.activate([
            outer.topAnchor.constraint(equalTo: content.topAnchor, constant: 20),
            outer.leadingAnchor.constraint(equalTo: content.leadingAnchor, constant: 20),
            outer.trailingAnchor.constraint(equalTo: content.trailingAnchor, constant: -20),
            outer.bottomAnchor.constraint(equalTo: content.bottomAnchor, constant: -16),
            buttonRow.trailingAnchor.constraint(equalTo: outer.trailingAnchor),
        ])
    }

    private func buildGrid(rows: [(String, NSView)]) -> NSGridView {
        var gridRows: [[NSView]] = rows.map { (labelText, control) in
            let label = NSTextField(labelWithString: labelText + ":")
            label.alignment = .right
            label.setContentHuggingPriority(.defaultHigh, for: .horizontal)
            return [label, control]
        }
        let grid = NSGridView(views: gridRows)
        grid.column(at: 0).width = 130
        grid.column(at: 0).xPlacement = .trailing
        grid.column(at: 1).xPlacement = .leading
        grid.rowSpacing = 10
        grid.columnSpacing = 10
        return grid
    }

    // MARK: - Helpers

    private func colorWell(color: NSColor) -> NSColorWell {
        let well = NSColorWell()
        well.color = color
        well.widthAnchor.constraint(equalToConstant: 44).isActive = true
        well.heightAnchor.constraint(equalToConstant: 22).isActive = true
        return well
    }

    private func slider(min: Double, max: Double, value: Float) -> NSSlider {
        let s = NSSlider()
        s.minValue = min; s.maxValue = max
        s.floatValue = value
        s.widthAnchor.constraint(equalToConstant: 180).isActive = true
        return s
    }

    private func valueLabel(for value: Float, format: String) -> NSTextField {
        let label = NSTextField(labelWithString: String(format: format, value))
        label.widthAnchor.constraint(equalToConstant: 50).isActive = true
        return label
    }

    private func hStack(_ views: [NSView], spacing: CGFloat) -> NSStackView {
        let s = NSStackView(views: views)
        s.orientation = .horizontal
        s.spacing = spacing
        s.alignment = .centerY
        return s
    }

    // MARK: - Actions

    @objc private func stepperChanged(_ sender: NSStepper) {
        fontSizeField.stringValue = String(sender.intValue)
    }

    @objc private func fontSizeFieldChanged(_ sender: NSTextField) {
        let v = max(8, min(72, sender.integerValue))
        fontSizeStepper.intValue = Int32(v)
        sender.stringValue = String(v)
    }

    @objc private func fallSpeedChanged(_ sender: NSSlider) {
        fallSpeedLabel.stringValue = String(format: "%.2f×", sender.floatValue)
    }

    @objc private func cameraSpeedChanged(_ sender: NSSlider) {
        cameraSpeedLabel.stringValue = String(format: "%.2f×", sender.floatValue)
    }

    @objc private func ok(_ sender: Any) {
        applyToConfig()
        config.save()
        dismiss()
        onDismiss()
    }

    @objc private func cancel(_ sender: Any) {
        dismiss()
    }

    private func applyToConfig() {
        let selectedFamily = fontPopUp.titleOfSelectedItem ?? "Menlo"
        let members = NSFontManager.shared.availableMembers(ofFontFamily: selectedFamily) ?? []
        // Prefer bold variant; fall back to first available member
        let boldMember = members.first { ($0[2] as? String)?.lowercased().contains("bold") == true }
        let member = boldMember ?? members.first
        config.fontName = (member?[0] as? String) ?? (selectedFamily + "-Bold")

        config.fontSize             = Float(fontSizeStepper.intValue)
        config.foregroundColor      = foregroundWell.color
        config.glowColor            = glowWell.color
        config.backgroundColor      = backgroundWell.color
        config.fallSpeedMultiplier  = fallSpeedSlider.floatValue
        config.cameraSpeedMultiplier = cameraSpeedSlider.floatValue
        config.is3D                 = is3DCheckbox.state == .on
        let chars = characterSetField.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
        config.characterSet         = chars.isEmpty ? GlyphyxConfig.defaultCharacterSet : chars
    }

    private func dismiss() {
        guard let w = window else { return }
        if let parent = w.sheetParent {
            parent.endSheet(w)
        } else {
            w.orderOut(nil)
        }
    }
}
