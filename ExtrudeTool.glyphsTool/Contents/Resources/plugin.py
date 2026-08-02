# encoding: utf-8

from __future__ import division, print_function, unicode_literals

import math

import objc
from AppKit import (
	NSAttributedString,
	NSBezierPath,
	NSColor,
	NSControlStateValueOn,
	NSCursor,
	NSFont,
	NSForegroundColorAttributeName,
	NSFontAttributeName,
	NSMakeRect,
	NSMenuItem,
	NSPoint,
	NSSlider,
	NSTextAlignmentRight,
	NSTextField,
	NSView,
)
from GlyphsApp import Glyphs, GSNode, LINE, OFFCURVE
from GlyphsApp.plugins import SelectTool

DEFAULTS_DOMAIN = 'com.danielgamage.ExtrudeTool'
DEFAULTS_SHOW_INFO = DEFAULTS_DOMAIN + '.showInfo'
DEFAULTS_QUANTIZATION = DEFAULTS_DOMAIN + '.quantization'

# macOS 15 NSCursor frame-resize enums (NSCursor.h). Glyphs' PyObjC does not
# export these names, but frameResizeCursorFromPosition_inDirections_ works.
NSCursorFrameResizePositionTop = 1 << 0
NSCursorFrameResizePositionLeft = 1 << 1
NSCursorFrameResizePositionRight = 1 << 3
NSCursorFrameResizePositionTopLeft = (
	NSCursorFrameResizePositionTop | NSCursorFrameResizePositionLeft
)
NSCursorFrameResizePositionTopRight = (
	NSCursorFrameResizePositionTop | NSCursorFrameResizePositionRight
)
NSCursorFrameResizeDirectionsAll = (1 << 0) | (1 << 1)  # Inward | Outward

EXTRUDE_CURSOR_POSITIONS = (
	NSCursorFrameResizePositionRight,
	NSCursorFrameResizePositionTopRight,
	NSCursorFrameResizePositionTop,
	NSCursorFrameResizePositionTopLeft,
)


class ExtrudeTool(SelectTool):

	valueField = None

	@objc.python_method
	def settings(self):
		Glyphs.registerDefaults({
			DEFAULTS_SHOW_INFO: True,
			DEFAULTS_QUANTIZATION: 0,
		})
		self.name = Glyphs.localize({'en': u'Extrude'})
		self.keyboardShortcut = 'w'
		self.toolbarPosition = 52
		self._icon = 'ToolbarIconTemplate.pdf'
		self.resetDragState()

	@objc.python_method
	def resetDragState(self):
		self.willExtrude = False
		self.hoverCursor = None
		self.resetExtrusionState()
		self.dragStartPoint = NSPoint(0, 0)

	@objc.python_method
	def resetExtrusionState(self):
		self.isExtruding = False
		self.selectionValid = False
		self.canExtrude = False
		self.crossesBounds = False
		self.extrudeAngle = 0.0
		self.extrudeDistance = 0.0
		self.midpoint = NSPoint(0, 0)
		self.sortedSelection = []
		self.sortedSelectionCoords = []

	@objc.python_method
	def activate(self):
		pass

	@objc.python_method
	def deactivate(self):
		self.hoverCursor = None

	@objc.python_method
	def showExtrudeInfo(self):
		return bool(Glyphs.defaults[DEFAULTS_SHOW_INFO])

	@objc.python_method
	def setShowExtrudeInfo(self, value):
		Glyphs.defaults[DEFAULTS_SHOW_INFO] = bool(value)

	@objc.python_method
	def extrudeQuantization(self):
		return int(Glyphs.defaults[DEFAULTS_QUANTIZATION])

	@objc.python_method
	def setExtrudeQuantization(self, value):
		Glyphs.defaults[DEFAULTS_QUANTIZATION] = int(value)

	@objc.python_method
	def quantizationString(self):
		quantization = self.extrudeQuantization()
		return 'Off' if quantization == 0 else str(quantization)

	@objc.python_method
	def translatePoint_withDistance_(self, point, distance):
		return NSPoint(
			point.x + distance * math.cos(self.extrudeAngle),
			point.y + distance * math.sin(self.extrudeAngle),
		)

	@objc.python_method
	def validSelection(self, selection):
		if not selection:
			return False
		path = selection[0].parent
		if path.closed:
			return len(selection) < len(path.nodes)
		return True

	@objc.python_method
	def getSibling_next_(self, node, nextNode):
		path = node.parent
		index = path.nodes.index(node)
		length = len(path.nodes)

		if nextNode:
			siblingIndex = (index + 1) % length
			crossesBounds = siblingIndex == 0
		else:
			siblingIndex = (index - 1 + length) % length
			crossesBounds = siblingIndex == length - 1

		if not path.closed and crossesBounds:
			return node
		return path.nodes[siblingIndex]

	@objc.python_method
	def prevNode_(self, node):
		return self.getSibling_next_(node, False)

	@objc.python_method
	def nextNode_(self, node):
		return self.getSibling_next_(node, True)

	@objc.python_method
	def selectedNodes(self, layer):
		return [node for node in layer.selection if isinstance(node, GSNode)]

	@objc.python_method
	def sortSelection(self, layer, selection):
		return sorted(
			selection,
			key=lambda node: (layer.indexOfPath_(node.parent), node.parent.indexOfNode_(node)),
		)

	@objc.python_method
	def pointXY(self, point):
		if isinstance(point, (tuple, list)):
			return float(point[0]), float(point[1])
		return float(point.x), float(point.y)

	@objc.python_method
	def pathSegments(self, path):
		"""Yield (startNode, offcurveNodes, endNode) for every segment of the path."""
		nodes = list(path.nodes)
		onCurveIndices = [i for i, node in enumerate(nodes) if node.type != OFFCURVE]
		if len(onCurveIndices) < 2:
			return

		for position, startIndex in enumerate(onCurveIndices):
			if position + 1 < len(onCurveIndices):
				endIndex = onCurveIndices[position + 1]
			elif path.closed:
				endIndex = onCurveIndices[0]
			else:
				return

			offcurves = []
			index = (startIndex + 1) % len(nodes)
			while index != endIndex:
				offcurves.append(nodes[index])
				index = (index + 1) % len(nodes)

			yield nodes[startIndex], offcurves, nodes[endIndex]

	@objc.python_method
	def distanceToSegment(self, loc, startNode, offcurves, endNode):
		locX, locY = self.pointXY(loc)
		x0, y0 = self.pointXY(startNode.position)
		x3, y3 = self.pointXY(endNode.position)

		if len(offcurves) == 2:
			x1, y1 = self.pointXY(offcurves[0].position)
			x2, y2 = self.pointXY(offcurves[1].position)
			closest = float('inf')
			steps = 24
			for step in range(steps + 1):
				t = step / steps
				mt = 1 - t
				x = mt * mt * mt * x0 + 3 * mt * mt * t * x1 + 3 * mt * t * t * x2 + t * t * t * x3
				y = mt * mt * mt * y0 + 3 * mt * mt * t * y1 + 3 * mt * t * t * y2 + t * t * t * y3
				closest = min(closest, math.hypot(locX - x, locY - y))
			return closest

		dx = x3 - x0
		dy = y3 - y0
		lengthSquared = dx * dx + dy * dy
		if lengthSquared == 0:
			return math.hypot(locX - x0, locY - y0)
		t = max(0.0, min(1.0, ((locX - x0) * dx + (locY - y0) * dy) / lengthSquared))
		return math.hypot(locX - (x0 + t * dx), locY - (y0 + t * dy))

	@objc.python_method
	def clickTargetsExtrusion(self, layer, loc):
		selection = self.selectedNodes(layer)
		if not self.validSelection(selection):
			return False

		element = self.elementAtPoint_atLayer_(loc, layer)
		if isinstance(element, GSNode) and element in layer.selection:
			return True

		scale = self.editViewController().graphicView().scale()
		tolerance = (5 + Glyphs.handleSize * 2.5) / scale
		selectedNodeSet = set(selection)

		for path in {node.parent for node in selection}:
			for startNode, offcurves, endNode in self.pathSegments(path):
				if startNode not in selectedNodeSet or endNode not in selectedNodeSet:
					continue
				if self.distanceToSegment(loc, startNode, offcurves, endNode) < tolerance:
					return True

		return False

	@objc.python_method
	def resolveExtrusionSpan(self, layer, selection):
		"""Return (firstNode, lastNode, remainingSelection, crossesBounds, droppedNodes) or None."""
		if not selection:
			return None

		remainingSelection = list(self.sortSelection(layer, selection))
		firstNode = remainingSelection[0]
		lastNode = remainingSelection[-1]
		path = firstNode.parent
		droppedNodes = []

		if path.closed and path.nodes[0] in remainingSelection and path.nodes[-1] in remainingSelection:
			crossesBounds = True
			for node in path.nodes:
				if node in remainingSelection:
					lastNode = node
				else:
					break
			for node in reversed(path.nodes):
				if node in remainingSelection:
					firstNode = node
				else:
					break
		else:
			crossesBounds = False

		while firstNode.type == OFFCURVE:
			nextNode = self.nextNode_(firstNode)
			if nextNode is firstNode or nextNode not in remainingSelection:
				return None
			droppedNodes.append(firstNode)
			remainingSelection.remove(firstNode)
			firstNode = nextNode

		while lastNode.type == OFFCURVE:
			prevNode = self.prevNode_(lastNode)
			if prevNode is lastNode or prevNode not in remainingSelection:
				return None
			droppedNodes.append(lastNode)
			remainingSelection.remove(lastNode)
			lastNode = prevNode

		if not remainingSelection:
			return None

		return firstNode, lastNode, remainingSelection, crossesBounds, droppedNodes

	@objc.python_method
	def extrusionAngle(self, layer):
		selection = self.selectedNodes(layer)
		if not self.validSelection(selection):
			return None
		span = self.resolveExtrusionSpan(layer, selection)
		if span is None:
			return None
		firstNode, lastNode = span[0], span[1]
		return math.atan2(
			lastNode.y - firstNode.y,
			lastNode.x - firstNode.x,
		) - math.pi / 2.0

	@objc.python_method
	def cursorForExtrusionAngle(self, angle):
		if angle is None:
			bucket = 0
		else:
			bucket = int(round((math.degrees(angle) % 180) / 45.0)) % 4
		position = EXTRUDE_CURSOR_POSITIONS[bucket]
		return NSCursor.frameResizeCursorFromPosition_inDirections_(
			position, NSCursorFrameResizeDirectionsAll
		)

	@objc.python_method
	def inheritedStandardCursor(self):
		cursor = objc.super(ExtrudeTool, self).standardCursor()
		if cursor is not None:
			return cursor
		return NSCursor.arrowCursor()

	@objc.python_method
	def updateHoverCursor(self, layer, loc):
		controller = self.editViewController()
		if controller is None:
			return
		if layer is not None and self.clickTargetsExtrusion(layer, loc):
			self.hoverCursor = self.cursorForExtrusionAngle(self.extrusionAngle(layer))
		else:
			self.hoverCursor = None
		controller.graphicView().setCursor_(self.hoverCursor or self.inheritedStandardCursor())

	@objc.python_method
	def updateHoverCursorForEvent(self, theEvent):
		controller = self.editViewController()
		if controller is None:
			return
		graphicView = controller.graphicView()
		self.updateHoverCursor(graphicView.activeLayer(), graphicView.getActiveLocation_(theEvent))

	def standardCursor(self):
		if self.hoverCursor is not None:
			return self.hoverCursor
		return self.inheritedStandardCursor()

	# GSToolSelect does its own highlighting in mouseMoved: and ends it by pushing
	# standardCursor into the view, so the hover state has to be up to date before
	# calling super.
	def mouseMoved_(self, theEvent):
		self.updateHoverCursorForEvent(theEvent)
		objc.super(ExtrudeTool, self).mouseMoved_(theEvent)

	def updateHighlightedElement_event_(self, layer, event):
		objc.super(ExtrudeTool, self).updateHighlightedElement_event_(layer, event)
		if event is not None:
			self.updateHoverCursorForEvent(event)

	@objc.python_method
	def beginExtrusion(self, layer):
		self.resetExtrusionState()
		selection = self.selectedNodes(layer)
		self.selectionValid = self.validSelection(selection)
		if not self.selectionValid:
			return

		span = self.resolveExtrusionSpan(layer, selection)
		if span is None:
			self.selectionValid = False
			return

		firstNode, lastNode, remainingSelection, crossesBounds, droppedNodes = span
		path = firstNode.parent

		for node in droppedNodes:
			layer.removeObjectFromSelection_(node)

		self.isExtruding = True
		self.editViewController().setShadowLayer_(layer.copy())
		self.sortedSelection = remainingSelection
		self.crossesBounds = crossesBounds

		self.midpoint = NSPoint(
			(lastNode.x + firstNode.x) / 2.0,
			(lastNode.y + firstNode.y) / 2.0,
		)
		self.extrudeAngle = math.atan2(
			lastNode.y - firstNode.y,
			lastNode.x - firstNode.x,
		) - math.pi / 2.0

		firstIndex = path.nodes.index(firstNode)
		lastIndex = path.nodes.index(lastNode) + 1
		firstHolder = firstNode.copy()
		lastHolder = lastNode.copy()

		if path.nodes[firstIndex].type != OFFCURVE and path.nodes[lastIndex - 1].type != OFFCURVE:
			self.canExtrude = True
		else:
			self.canExtrude = False

		for node in self.sortedSelection:
			self.sortedSelectionCoords.append(node.positionPrecise())

		if self.canExtrude:
			offset = 1 if self.crossesBounds else 0
			path.insertObject_inNodesAtIndex_(firstHolder, firstIndex)
			path.insertObject_inNodesAtIndex_(lastHolder, lastIndex + 1 - offset)

			path.nodes[firstIndex + offset].smooth = False
			path.nodes[firstIndex + offset + 1].smooth = False
			path.nodes[firstIndex + offset + 1].type = LINE

			path.nodes[lastIndex - offset].smooth = False
			path.nodes[lastIndex - offset + 1].smooth = False
			path.nodes[lastIndex - offset + 1].type = LINE

	def mouseDown_(self, theEvent):
		graphicView = self.editViewController().graphicView()
		layer = graphicView.activeLayer()
		loc = graphicView.getActiveLocation_(theEvent)

		self.willExtrude = self.clickTargetsExtrusion(layer, loc)
		if self.willExtrude:
			self.dragStartPoint = loc
			graphicView.setCursor_(self.cursorForExtrusionAngle(self.extrusionAngle(layer)))
		else:
			objc.super(ExtrudeTool, self).mouseDown_(theEvent)

	def mouseDragged_(self, theEvent):
		if not self.willExtrude:
			objc.super(ExtrudeTool, self).mouseDragged_(theEvent)
			return

		graphicView = self.editViewController().graphicView()
		layer = graphicView.activeLayer()
		mousePosition = graphicView.getActiveLocation_(theEvent)

		if not self.isExtruding:
			self.beginExtrusion(layer)

		if self.canExtrude and self.selectionValid:
			deltaX = mousePosition.x - self.dragStartPoint.x
			deltaY = mousePosition.y - self.dragStartPoint.y
			self.extrudeDistance = deltaX * math.cos(self.extrudeAngle) + deltaY * math.sin(self.extrudeAngle)

			quantization = self.extrudeQuantization()
			if quantization != 0:
				self.extrudeDistance = round(self.extrudeDistance / quantization) * quantization

			for index, node in enumerate(self.sortedSelection):
				origin = self.sortedSelectionCoords[index]
				newPoint = self.translatePoint_withDistance_(origin, self.extrudeDistance)
				node.setPositionFast_(newPoint)
				layer.elementDidChange_(node)

	def mouseUp_(self, theEvent):
		if self.willExtrude:
			if self.canExtrude and self.selectionValid:
				if self.isExtruding:
					for index, node in enumerate(self.sortedSelection):
						newPos = node.positionPrecise()
						origin = self.sortedSelectionCoords[index]
						node.setPositionFast_(origin)
						node.position = newPos
				self.editViewController().setShadowLayer_(None)
		else:
			objc.super(ExtrudeTool, self).mouseUp_(theEvent)

		self.resetDragState()
		self.updateHoverCursorForEvent(theEvent)

	def toggleExtrudeInfo_(self, sender):
		self.setShowExtrudeInfo(not self.showExtrudeInfo())

	def updateQuantization_(self, sender):
		slider = sender
		self.setExtrudeQuantization(int(slider.doubleValue()))
		if self.valueField is not None:
			self.valueField.setStringValue_(self.quantizationString())

	def addMenuItemsForEvent_toMenu_(self, theEvent, theMenu):
		objc.super(ExtrudeTool, self).addMenuItemsForEvent_toMenu_(theEvent, theMenu)

		extrudeInfoItem = NSMenuItem.alloc().initWithTitle_action_keyEquivalent_(
			'Extrude Info', 'toggleExtrudeInfo:', ''
		)
		extrudeSliderItem = NSMenuItem.alloc().initWithTitle_action_keyEquivalent_(
			'Extrude Snapping', None, ''
		)

		viewRect = NSMakeRect(0, 0, 184, 48)
		sliderView = NSView.alloc().initWithFrame_(viewRect)
		margin = 20

		labelRect = NSMakeRect(margin, 22, sliderView.frame().size.width - margin, 24)
		labelField = NSTextField.alloc().initWithFrame_(labelRect)
		labelField.setStringValue_('Extrusion Snapping')
		labelField.setFont_(NSFont.menuFontOfSize_(11))
		labelField.setBezeled_(False)
		labelField.setDrawsBackground_(False)
		labelField.setEditable_(False)
		labelField.setSelectable_(False)
		labelField.setTextColor_(NSColor.darkGrayColor())
		sliderView.addSubview_(labelField)

		sliderRect = NSMakeRect(margin, 0, 121, 24)
		slider = NSSlider.alloc().initWithFrame_(sliderRect)
		slider.setDoubleValue_(float(self.extrudeQuantization()))
		slider.setMinValue_(0.0)
		slider.setMaxValue_(10.0)
		slider.setAction_('updateQuantization:')
		slider.setContinuous_(True)
		slider.setNumberOfTickMarks_(11)
		slider.setAllowsTickMarkValuesOnly_(True)
		slider.setTarget_(self)
		sliderView.addSubview_(slider)

		valueRect = NSMakeRect(
			slider.frame().origin.x + slider.frame().size.width,
			0,
			viewRect.size.width - slider.frame().origin.x - slider.frame().size.width - 15,
			26,
		)
		self.valueField = NSTextField.alloc().initWithFrame_(valueRect)
		self.valueField.setAlignment_(NSTextAlignmentRight)
		self.valueField.setStringValue_(self.quantizationString())
		self.valueField.setBezeled_(False)
		self.valueField.setDrawsBackground_(False)
		self.valueField.setEditable_(False)
		self.valueField.setSelectable_(False)
		sliderView.addSubview_(self.valueField)

		if self.showExtrudeInfo():
			extrudeInfoItem.setState_(NSControlStateValueOn)
		extrudeSliderItem.setView_(sliderView)

		theMenu.addItem_(NSMenuItem.separatorItem())
		theMenu.addItem_(extrudeInfoItem)
		theMenu.addItem_(extrudeSliderItem)
		theMenu.addItem_(NSMenuItem.separatorItem())

	@objc.python_method
	def foreground(self, layer):
		if not (self.isExtruding and self.showExtrudeInfo()):
			return

		scale = self.editViewController().graphicView().scale()
		midpointWithDistance = self.translatePoint_withDistance_(self.midpoint, self.extrudeDistance)
		midpointTranslated = NSPoint(midpointWithDistance.x, midpointWithDistance.y)

		textAttributes = {
			NSFontAttributeName: NSFont.labelFontOfSize_(10.0 / scale),
			NSForegroundColorAttributeName: NSColor.whiteColor(),
		}
		line1 = '%.2f' % self.extrudeDistance
		line2 = '%.2f°' % (self.extrudeAngle * 180.0 / math.pi)
		text = '%s\n%s' % (line1, line2)
		displayText = NSAttributedString.alloc().initWithString_attributes_(text, textAttributes)
		textLength = max(len(line1), len(line2))

		rectWidth = (textLength * 10 - 10) / scale
		rectHeight = 40.0 / scale
		midpointAdjusted = NSPoint(
			midpointTranslated.x - rectWidth / 2.0,
			midpointTranslated.y - rectHeight / 2.0,
		)

		NSColor.colorWithCalibratedRed_green_blue_alpha_(0.0, 0.6, 1.0, 0.75).set()
		dirtyRect = NSMakeRect(midpointAdjusted.x, midpointAdjusted.y, rectWidth, rectHeight)
		path = NSBezierPath.bezierPathWithRoundedRect_xRadius_yRadius_(
			dirtyRect, 8.0 / scale, 8.0 / scale
		)
		path.fill()
		displayText.drawAtPoint_(NSPoint(midpointAdjusted.x + 8.0 / scale, midpointAdjusted.y + 6.0 / scale))

	@objc.python_method
	def __file__(self):
		"""Please leave this method unchanged"""
		return __file__
