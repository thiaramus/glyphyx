import AppKit
import ScreenSaver

final class ConfigureSheetController: NSWindowController {

    private let config:    GlyphyxConfig
    private let onDismiss: () -> Void

    private var fontPopUp:         NSPopUpButton!
    private var fontSizeField:     NSTextField!
    private var fontSizeStepper:   NSStepper!
    private var foregroundWell:    NSColorWell!
    private var glowWell:          NSColorWell!
    private var backgroundWell:    NSColorWell!
    private var fallSpeedSlider:   NSSlider!
    private var fallSpeedLabel:    NSTextField!
    private var is3DCheckbox:      NSButton!
    private var flowDirectionPopUp: NSPopUpButton!
    private var bidirectionalLayoutPopUp: NSPopUpButton!
    private var cameraSpeedSlider: NSSlider!
    private var cameraSpeedLabel:  NSTextField!
    private var characterSetField: NSTextField!

    private var cameraSpeedRow: NSView!
    private var bidirectionalLayoutRow: NSView!
    private var outerStack:     NSStackView!

    private let labelWidth: CGFloat = 130
    private let hPad:       CGFloat = 20
    private let vPadTop:    CGFloat = 20
    private let vPadBot:    CGFloat = 16

    init(config: GlyphyxConfig, onDismiss: @escaping () -> Void) {
        self.config    = config
        self.onDismiss = onDismiss

        let w = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: 460, height: 400),
            styleMask:   [.titled, .closable],
            backing:     .buffered,
            defer:       false
        )
        w.title = "Glyphyx Settings"
        w.isReleasedWhenClosed = false
        super.init(window: w)
        buildUI()
        fitWindow(animated: false)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) not supported") }

    // MARK: - UI Construction

    private func buildUI() {
        guard let content = window?.contentView else { return }

        // Font family
        fontPopUp = NSPopUpButton()
        let monoFamilies: [String] = {
            let known: Set<String> = ["Menlo", "Courier", "Courier New", "Monaco", "PT Mono",
                                      "SF Mono", "Source Code Pro", "Fira Code", "JetBrains Mono",
                                      "Hack", "Inconsolata", "IBM Plex Mono", "Roboto Mono",
                                      "Cascadia Code", "Anonymous Pro"]
            var result = NSFontManager.shared.availableFontFamilies.filter {
                known.contains($0) ||
                $0.lowercased().contains("mono") ||
                $0.lowercased().contains("code") ||
                $0.lowercased().contains("courier")
            }
            if let fam = NSFont(name: config.fontName, size: 12)?.familyName,
               !result.contains(fam) { result.append(fam) }
            return result.sorted()
        }()
        monoFamilies.forEach { fontPopUp.addItem(withTitle: $0) }
        fontPopUp.selectItem(withTitle: NSFont(name: config.fontName, size: 12)?.familyName ?? "Menlo")

        // Font size — set TAMIC=false before activating dimension constraints
        fontSizeField = NSTextField()
        fontSizeField.stringValue = String(Int(config.fontSize))
        fontSizeField.translatesAutoresizingMaskIntoConstraints = false
        fontSizeField.widthAnchor.constraint(equalToConstant: 48).isActive = true

        fontSizeStepper = NSStepper()
        fontSizeStepper.minValue  = 8; fontSizeStepper.maxValue = 72
        fontSizeStepper.increment = 1
        fontSizeStepper.intValue  = Int32(config.fontSize)
        fontSizeStepper.target = self; fontSizeStepper.action = #selector(stepperChanged(_:))
        fontSizeField.target   = self; fontSizeField.action   = #selector(fontSizeFieldChanged(_:))

        // Colors
        foregroundWell = colorWell(color: config.foregroundColor)
        glowWell       = colorWell(color: config.glowColor)
        backgroundWell = colorWell(color: config.backgroundColor)

        // Fall speed
        fallSpeedSlider = makeSlider(min: 0.25, max: 4.0, value: config.fallSpeedMultiplier)
        fallSpeedLabel  = valueLabel(config.fallSpeedMultiplier)
        fallSpeedSlider.target = self; fallSpeedSlider.action = #selector(fallSpeedChanged(_:))

        // 3D toggle — wired so toggling shows/hides camera speed row
        is3DCheckbox = NSButton(checkboxWithTitle: "Enable 3D mode",
                                target: self, action: #selector(is3DChanged(_:)))
        is3DCheckbox.state = config.is3D ? .on : .off

        flowDirectionPopUp = NSPopUpButton()
        FlowDirection.allCases.forEach { flowDirectionPopUp.addItem(withTitle: $0.title) }
        flowDirectionPopUp.selectItem(at: config.flowDirection.rawValue)
        flowDirectionPopUp.target = self
        flowDirectionPopUp.action = #selector(flowDirectionChanged(_:))

        bidirectionalLayoutPopUp = NSPopUpButton()
        BidirectionalLayout.allCases.forEach { bidirectionalLayoutPopUp.addItem(withTitle: $0.title) }
        bidirectionalLayoutPopUp.selectItem(at: config.bidirectionalLayout.rawValue)

        // Camera speed
        cameraSpeedSlider = makeSlider(min: 0.0, max: 3.0, value: config.cameraSpeedMultiplier)
        cameraSpeedLabel  = valueLabel(config.cameraSpeedMultiplier)
        cameraSpeedSlider.target = self; cameraSpeedSlider.action = #selector(cameraSpeedChanged(_:))

        // Character set
        characterSetField = NSTextField()
        characterSetField.stringValue       = config.characterSet
        characterSetField.placeholderString = "Characters used in the animation"
        characterSetField.font = NSFont.monospacedSystemFont(ofSize: 11, weight: .regular)

        // Compound controls
        let fontSizeCtrl  = hStack([fontSizeField, fontSizeStepper],             spacing: 4)
        let fallCtrl      = hStack([fallSpeedSlider, fallSpeedLabel],             spacing: 8)
        let cameraCtrl    = hStack([cameraSpeedSlider, cameraSpeedLabel],         spacing: 8)

        // Form rows — each is a horizontal stack: [label (fixed width) | control]
        // Camera speed row is tracked so it can be hidden
        bidirectionalLayoutRow = formRow("Split Pattern", bidirectionalLayoutPopUp)
        bidirectionalLayoutRow.isHidden = config.flowDirection != .bothDirections
        cameraSpeedRow         = formRow("Camera Speed", cameraCtrl)
        cameraSpeedRow.isHidden = !config.is3D

        let formStack = NSStackView(views: [
            formRow("Font",             fontPopUp),
            formRow("Font Size",        fontSizeCtrl),
            formRow("Foreground Color", foregroundWell),
            formRow("Glow Color",       glowWell),
            formRow("Background Color", backgroundWell),
            formRow("Fall Speed",       fallCtrl),
            formRow("Flow Direction",   flowDirectionPopUp),
            bidirectionalLayoutRow,
            formRow("Animation Mode",   is3DCheckbox),
            cameraSpeedRow,
            formRow("Character Set",    characterSetField),
        ])
        formStack.orientation = .vertical
        formStack.spacing     = 10
        formStack.alignment   = .leading

        // Buttons: [Defaults] — — — [Cancel] [OK]
        let defaultsBtn = NSButton(title: "Defaults", target: self, action: #selector(resetToDefaults(_:)))
        defaultsBtn.bezelStyle = .rounded
        let cancelBtn = NSButton(title: "Cancel", target: self, action: #selector(cancel(_:)))
        cancelBtn.bezelStyle = .rounded
        let okBtn = NSButton(title: "OK", target: self, action: #selector(ok(_:)))
        okBtn.bezelStyle    = .rounded
        okBtn.keyEquivalent = "\r"

        let btnStack = NSStackView()
        btnStack.orientation = .horizontal
        btnStack.spacing     = 8
        btnStack.addView(defaultsBtn, in: .leading)
        btnStack.addView(cancelBtn,   in: .trailing)
        btnStack.addView(okBtn,       in: .trailing)

        // Outer vertical stack
        outerStack = NSStackView(views: [formStack, btnStack])
        outerStack.orientation = .vertical
        outerStack.spacing     = 16
        outerStack.alignment   = .leading

        outerStack.translatesAutoresizingMaskIntoConstraints = false
        content.addSubview(outerStack)
        NSLayoutConstraint.activate([
            outerStack.topAnchor.constraint(equalTo: content.topAnchor, constant: vPadTop),
            outerStack.leadingAnchor.constraint(equalTo: content.leadingAnchor, constant: hPad),
            outerStack.trailingAnchor.constraint(equalTo: content.trailingAnchor, constant: -hPad),
            btnStack.trailingAnchor.constraint(equalTo: outerStack.trailingAnchor),
        ])
    }

    // MARK: - Layout helpers

    /// A horizontal row: right-aligned label (fixed width) + control.
    private func formRow(_ labelText: String, _ control: NSView) -> NSView {
        let lbl = NSTextField(labelWithString: labelText + ":")
        lbl.alignment = .right
        lbl.translatesAutoresizingMaskIntoConstraints = false
        lbl.widthAnchor.constraint(equalToConstant: labelWidth).isActive = true

        let row = NSStackView(views: [lbl, control])
        row.orientation = .horizontal
        row.spacing     = 10
        row.alignment   = .centerY
        return row
    }

    private func colorWell(color: NSColor) -> NSColorWell {
        let w = NSColorWell()
        w.color = color
        w.translatesAutoresizingMaskIntoConstraints = false
        w.widthAnchor.constraint(equalToConstant: 44).isActive = true
        w.heightAnchor.constraint(equalToConstant: 22).isActive = true
        return w
    }

    private func makeSlider(min: Double, max: Double, value: Float) -> NSSlider {
        let s = NSSlider(value: Double(value), minValue: min, maxValue: max,
                         target: nil, action: nil)
        s.translatesAutoresizingMaskIntoConstraints = false
        s.widthAnchor.constraint(equalToConstant: 180).isActive = true
        return s
    }

    private func valueLabel(_ value: Float) -> NSTextField {
        let l = NSTextField(labelWithString: String(format: "%.2f×", value))
        l.translatesAutoresizingMaskIntoConstraints = false
        l.widthAnchor.constraint(equalToConstant: 52).isActive = true
        return l
    }

    private func hStack(_ views: [NSView], spacing: CGFloat) -> NSStackView {
        let s = NSStackView(views: views)
        s.orientation = .horizontal
        s.spacing     = spacing
        s.alignment   = .centerY
        return s
    }

    /// Resize the window to exactly fit the current content.
    private func fitWindow(animated: Bool) {
        guard let window = window else { return }
        window.contentView?.layoutSubtreeIfNeeded()
        let fit     = outerStack.fittingSize
        let newSize = NSSize(width: 460, height: fit.height + vPadTop + vPadBot)
        if animated {
            NSAnimationContext.runAnimationGroup { ctx in
                ctx.duration = 0.15
                window.animator().setContentSize(newSize)
            }
        } else {
            window.setContentSize(newSize)
        }
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

    @objc private func is3DChanged(_ sender: NSButton) {
        cameraSpeedRow.isHidden = sender.state != .on
        fitWindow(animated: true)
    }

    @objc private func flowDirectionChanged(_ sender: NSPopUpButton) {
        let selectedDirection = FlowDirection(rawValue: sender.indexOfSelectedItem) ?? .down
        bidirectionalLayoutRow.isHidden = selectedDirection != .bothDirections
        fitWindow(animated: true)
    }

    @objc private func resetToDefaults(_ sender: Any) {
        fontPopUp.selectItem(withTitle: NSFont(name: "Menlo-Bold", size: 12)?.familyName ?? "Menlo")
        fontSizeStepper.intValue  = 14
        fontSizeField.stringValue = "14"
        foregroundWell.color      = .white
        glowWell.color            = NSColor(red: 0.5, green: 0.8, blue: 1.0, alpha: 0.5)
        backgroundWell.color      = .black
        fallSpeedSlider.floatValue   = 1.0
        fallSpeedLabel.stringValue   = "1.00×"
        flowDirectionPopUp.selectItem(at: FlowDirection.down.rawValue)
        bidirectionalLayoutPopUp.selectItem(at: BidirectionalLayout.screenHalves.rawValue)
        cameraSpeedSlider.floatValue = 1.0
        cameraSpeedLabel.stringValue = "1.00×"
        is3DCheckbox.state            = .off
        characterSetField.stringValue = GlyphyxConfig.defaultCharacterSet
        bidirectionalLayoutRow.isHidden = true
        cameraSpeedRow.isHidden = true
        fitWindow(animated: true)
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
        let members        = NSFontManager.shared.availableMembers(ofFontFamily: selectedFamily) ?? []
        let boldMember     = members.first { ($0[2] as? String)?.lowercased().contains("bold") == true }
        let member         = boldMember ?? members.first
        config.fontName    = (member?[0] as? String) ?? (selectedFamily + "-Bold")

        config.fontSize              = Float(fontSizeStepper.intValue)
        config.foregroundColor       = foregroundWell.color
        config.glowColor             = glowWell.color
        config.backgroundColor       = backgroundWell.color
        config.fallSpeedMultiplier   = fallSpeedSlider.floatValue
        config.flowDirection         = FlowDirection(rawValue: flowDirectionPopUp.indexOfSelectedItem) ?? .down
        config.bidirectionalLayout   = BidirectionalLayout(rawValue: bidirectionalLayoutPopUp.indexOfSelectedItem) ?? .screenHalves
        config.cameraSpeedMultiplier = cameraSpeedSlider.floatValue
        config.is3D                  = is3DCheckbox.state == .on
        let chars = characterSetField.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
        config.characterSet = chars.isEmpty ? GlyphyxConfig.defaultCharacterSet : chars
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
