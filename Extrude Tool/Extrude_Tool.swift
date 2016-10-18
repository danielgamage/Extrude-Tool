//
//  Extrude_Tool.swift
//  Extrude Tool
//
//  Created by Daniel Gamage on 10/16/16.
//  Copyright © 2016 Daniel Gamage. All rights reserved.
//

import Foundation
import Cocoa

class Extrude_Tool: GlyphsPathPlugin {
    var extrudeAngle: Double
    var extrudeDistance: Double
    var extrudeQuantization: Double
    var canExtrude: Bool
    var selectionValid: Bool
    var crossesBounds: Bool
    var extrudeInfo: Bool
    var pathDirection: GSPathDirection
    var mousePosition: NSPoint
    var midpoint: NSPoint
    var bgPath: NSBezierPath
    var layer: GSLayer
    var sortedSelection: Array<GSNode>
    var sortedSelectionCoords: Array<NSPoint>
    var extrudeQuantizationString: String
    var valueField: NSTextField
    var editView: GSGlyphEditViewProtocol

    init() {
        super.init()
        var thisBundle : Bundle? = Bundle.main
        if thisBundle != nil {
            // The toolbar icon:
            toolBarIcon = NSImage(contentsOfFile: thisBundle.pathForImageResource("ToolbarIconTemplate"))
            toolBarIcon.isTemplate = true
        }
        extrudeInfo = true
        canExtrude = false
        selectionValid = false
        dragging = false
        extrudeAngle = 0
        extrudeDistance = 0
        extrudeQuantization = 0
        sortedSelectionCoords = []
        editView = ((editViewController as! GSGlyphEditViewControllerProtocol).graphicView as! GSGlyphEditViewProtocol)
    }

    func interfaceVersion() -> Int {
        // Distinguishes the API verison the plugin was built for. Return 1.
        return 1
    }

    func groupID() -> Int {
        // Return a number between 50 and 1000 to position the icon in the toolbar.
        return 20
    }

    func title() -> String! {
        // return the name of the tool as it will appear in the tooltip of in the toolbar.
        return "Extrude"
    }

    func trigger() -> String! {
        // Return the key that the user can press to activate the tool.
        // Please make sure to not conflict with other tools.
        return "w"
    }

    func toggleHUD() {
        extrudeInfo = extrudeInfo ? false : true
    }

    func addMenuItemsForEvent(theEvent: NSEvent, toMenu theMenu: NSMenu) {
        // Adds an item to theMenu for theEvent.
        let extrudeInfoItem = NSMenuItem(title: "Extrude Info", action: #selector(Extrude_Tool.toggleHUD), keyEquivalent: "")
        let extrudeSliderItem = NSMenuItem(title: "Extrude Snapping", action: nil, keyEquivalent: "")

        // Make view for Quantization slider
        let viewRect = NSMakeRect(0, 0, 196, 52)
        let sliderView = NSView(frame: viewRect)
        let margin = CGFloat(20)

        // Label above
        let labelRect = NSMakeRect(margin, 22, sliderView.frame.size.width - margin, 26)
        let labelField = NSTextField(frame: labelRect)
        labelField.stringValue = "Extrusion Snapping"
        labelField.isBezeled = false
        labelField.drawsBackground = false
        labelField.isEditable = false
        labelField.isSelectable = false
        labelField.textColor = NSColor.darkGray
        sliderView.addSubview(labelField)

        // Slider input
        let sliderRect = NSMakeRect(margin, 0, 121, 26)
        let slider = NSSlider(frame: sliderRect)
        slider.doubleValue = extrudeQuantization
        slider.minValue = 0.00
        slider.maxValue = 10.00
        slider.action = Selector(("updateQuantization:"))
        slider.isContinuous = true
        slider.numberOfTickMarks = 11
        slider.allowsTickMarkValuesOnly = true
        slider.target = self
        sliderView.addSubview(slider)

        // Slider value
        let valueRect = NSMakeRect(slider.frame.origin.x + slider.frame.size.width, 0, viewRect.size.width - slider.frame.origin.x - slider.frame.size.width - margin, 26)
        valueField = NSTextField(frame: valueRect)
        valueField.alignment = NSTextAlignment.right
        valueField.stringValue = updateQuantizationString()
        valueField.isBezeled = false
        valueField.drawsBackground = false
        valueField.isEditable = false
        valueField.isSelectable = false
        sliderView.addSubview(valueField)

        extrudeInfoItem.state = extrudeInfo ? NSOnState : NSOffState

        extrudeSliderItem.view = sliderView

        theMenu.addItem(NSMenuItem.separator())
        theMenu.addItem(extrudeInfoItem)
        theMenu.addItem(extrudeSliderItem)
    }

    func updateQuantization(sender: AnyObject) {
        let slider = sender as! NSSlider
        extrudeQuantization = slider.doubleValue
        extrudeQuantizationString = updateQuantizationString()
        valueField.stringValue = extrudeQuantizationString
    }

    func updateQuantizationString() -> String {
        return (extrudeQuantization == 0) ? "Off" : "\(Int(extrudeQuantization))"
    }

    func translatePoint(node: CGPoint, distance: Double) -> NSPoint {
        let x = node.x + CGFloat(distance) * cos(CGFloat(extrudeAngle))
        let y = node.y + CGFloat(distance) * sin(CGFloat(extrudeAngle))
        return NSMakePoint(x, y)
    }

    func validSelection(selection: NSMutableOrderedSet) -> Bool {
        if selection.count > 0 {
            let node : GSNode = selection.first as! GSNode
            let path: GSPath = node.parent as! GSPath
            if path.closed {
                return (selection.count < path.nodes.count)
            } else {
                return true
            }
        } else {
            return false
        }
    }

    func mouseDragged(theEvent: NSEvent) {
        // Called when the mouse is moved with the primary button down.
        layer = (editViewController as! GSGlyphEditViewControllerProtocol).activeLayer
        mousePosition = editView.getActiveLocation(theEvent)

        if !dragging {
            // Run the first time the user draggs. Otherwise it would insert the extra nodes if the user only clicks.
            // layer.selection.count: Ensure there is a selection before running operations on the selection
            selectionValid = self.validSelection(selection: layer.selection)

            if selectionValid {
                dragging = true
                draggStart = editView.getActiveLocation(theEvent)

                // Set background before manipulating activeLayer
                (editViewController as! GSGlyphEditViewControllerProtocol).shadowLayer = layer
                sortedSelection = layer.selection.sortedArray(comparator: { (a: GSNode, b: GSNode) -> ComparisonResult in
                    // Sort by path parent
                    var first = layer.indexOfPath(a.parent)
                    var second = layer.indexOfPath(b.parent)
                    if first > second {
                        return NSOrderedDescending
                    }
                    if first < second {
                        return NSOrderedAscending
                    }

                    // Then sort by node index
                    first = a.parent.indexOfNode(a)
                    second = b.parent.indexOfNode(b)
                    if first > second {
                        return NSOrderedDescending
                    }
                    if first < second {
                        return NSOrderedAscending
                    }
                    return NSOrderedSame
                } as! (Any, Any) -> ComparisonResult)

                for node: GSNode in sortedSelection {
                    sortedSelectionCoords.append(node.positionPrecise)
                }

                var firstNode : GSNode = sortedSelection.first as GSNode!
                var lastNode : GSNode = sortedSelection.last as GSNode!
                var path : GSPath = firstNode.parent as! GSPath!

                // If first & last nodes are selected, the selection crosses bounds of the array
                if path.closed && sortedSelection.contains(path.nodes.first!) && sortedSelection.contains(path.nodes.last!) {
                    crossesBounds = true

                    // Reassign first and last nodes accordingly
                    var i = 0
                    while sortedSelection.contains(path.nodes[i]) {
                        lastNode = path.nodes[i]
                        i += 1
                    }

                    var d = path.nodes.count - 1;
                    while sortedSelection.contains(path.nodes[d]) {
                        firstNode = path.nodes[d]
                        d -= 1
                    }
                } else {
                    crossesBounds = false
                }

                // Get midpoint between first and last nodes
                midpoint = NSMakePoint(((lastNode.position.x + firstNode.position.x) / 2), ((lastNode.position.y + firstNode.position.y) / 2))

                // Get angle at which to extrude
                extrudeAngle = atan2(Double(lastNode.position.y - firstNode.position.y), Double(lastNode.position.x - firstNode.position.x)) - M_PI_2

                pathDirection = path.direction() as GSPathDirection

                var firstIndex = Int(path.index(of: firstNode))
                var lastIndex = Int(path.index(of: lastNode) + 1)
                var firstHolder = firstNode
                var lastHolder = lastNode

                // Disallow Extrusion if first and last nodes in selection are OFFCURVE
                if path.node(at: firstIndex).type != .OFFCURVE && path.node(at: lastIndex - 1).type != .OFFCURVE {
                    canExtrude = true
                } else {
                    canExtrude = false
                }

                if canExtrude == true {
                    var offset = crossesBounds ? 1 : 0

                    // Insert nodes at front and back of selection
                    // shift the last index +1 because a node was inserted before it,
                    // or don't if the selection crosses bounds (the first / last nodes are effectively flipped)
                    path.insertNode(firstHolder, at: firstIndex)
                    path.insertNode(lastHolder, at: lastIndex + 1 - offset)

                    path.node(at: firstIndex + offset).connection = .SHARP
                    path.node(at: firstIndex + offset + 1).connection = .SHARP
                    path.node(at: firstIndex + offset + 1).type = .LINE

                    path.node(at: lastIndex - offset).connection = .SHARP
                    path.node(at: lastIndex - offset + 1).connection = .SHARP
                    path.node(at: lastIndex - offset + 1).type = .LINE
                }
            }
        }
        if canExtrude && selectionValid {

            // Use mouse position on x axis to translate the points
            // should counter-act path direction
            extrudeDistance = Double(Float(mousePosition.x) - Float(draggStart.x)) * Double(Int(pathDirection.rawValue) * -1)

            // Quantize to nearest multiple of quantize value
            if extrudeQuantization != 0 {
                extrudeDistance = round(extrudeDistance / extrudeQuantization) * extrudeQuantization
            }

            var index = 0
            for node: GSNode in sortedSelection {
                var origin = sortedSelectionCoords[index]
                var newPoint = translatePoint(node: origin, distance: extrudeDistance)
                // setPositionFast so not EVERY update is logged in history.
                // force paint in elementDidChange because setPositionFast doesn't notify
                node.setPositionFast(newPoint)
                layer.elementDidChange(node)
                index += 1
            }
        }
    }

    func mouseUp(theEvent: NSEvent) {
        // Called when the primary mouse button is released.

        if canExtrude && selectionValid {
            if dragging {
                var index = 0
                for node: GSNode in sortedSelection {
                    let newPos = node.positionPrecise
                    let origin = sortedSelectionCoords[index]
                    // revert to origin first so that history log shows move from point@origin to point@newPos, instead of form wherever mouseDragged left off
                    node.setPositionFast(origin)
                    node.position = newPos
                    index += 1
                }
            }
            // Empty coordinate cache
            sortedSelectionCoords.removeAll()
            // Remove background contents
            (editViewController as! GSGlyphEditViewControllerProtocol).shadowLayer = nil
        }
        dragging = false
    }
    override func drawForeground() {
        // Draw in the foreground, concerns the complete view.

        // Only show if option to show Extrude HUD is checked
        if (dragging && extrudeInfo) {
            // Adapted from https://github.com/Mark2Mark/Show-Distance-And-Angle-Of-Nodes
            let scale = editView.scale

            // Translate & scale midpoint
            let midpointWithDistance = translatePoint(node: midpoint, distance: extrudeDistance)
            let midpointTranslated = NSMakePoint(((midpointWithDistance.x) * scale), ((midpointWithDistance.y - layer.glyphMetrics().ascender) * scale))

            // Define text
            let textAttributes = [
                NSFontAttributeName: NSFont.labelFont(ofSize: 10),
                NSForegroundColorAttributeName: NSColor.white,
            ]
            let line1 = String(format: "%.2f", extrudeDistance)
            let line2 = String(format: "%.2f°", extrudeAngle * 180 / M_PI)
            let text = "\(line1)\n\(line2)"
            let displayText = NSAttributedString(string: text, attributes: textAttributes)
            // Get greater of the two line letter-counts
            let textLength = max(line1.characters.count, line2.characters.count)

            let rectWidth = CGFloat(textLength * 10 - 10)
            let rectHeight = CGFloat(40)

            let midpointAdjusted = NSMakePoint(midpointTranslated.x - CGFloat(rectWidth / 2), midpointTranslated.y - CGFloat(rectHeight / 2))

            // Draw rectangle bg
            let myPath = NSBezierPath()
            NSColor(red: 0, green: 0.6, blue: 1, alpha: 0.75).set()
            let dirtyRect = NSMakeRect(midpointAdjusted.x, midpointAdjusted.y, rectWidth, rectHeight)
            myPath.appendRoundedRect(dirtyRect, xRadius: 8, yRadius: 8)
            myPath.append(myPath)
            myPath.fill()

            // Draw text
            displayText.draw(at: NSMakePoint(midpointAdjusted.x + 8, midpointAdjusted.y + 6))
        }

    }

    func drawLayer(Layer: GSLayer, aPoint: NSPoint, Active: Bool, Attributes: NSDictionary!) {
        // Draw anythin for this particular layer.
        super.draw(Layer, at:aPoint, asActive:Active, attributes:Attributes as! [AnyHashable : Any]!)
    }

    override func willActivate() {
        // Called when the tool is selected by the user.
        editView.cursor = NSCursor.resizeLeftRight();
    }

    override func willDeactivate() {}

}
