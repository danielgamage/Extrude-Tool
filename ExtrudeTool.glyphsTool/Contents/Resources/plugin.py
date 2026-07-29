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
		self.isExtruding = False
		self.selectionValid = False
		self.canExtrude = False
		self.crossesBounds = False
		self.extrudeAngle = 0.0
		self.extrudeDistance = 0.0
		self.midpoint = NSPoint(0, 0)
		self.sortedSelection = []
		self.sortedSelectionCoords = []
		self.pathDirection = 1
		self.dragStartPoint = NSPoint(0, 0)

	@objc.python_method
	def activate(self):
		self.editViewController().graphicView().setCursor_(NSCursor.resizeLeftRightCursor())

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
	def beginExtrusion(self, layer):
		self.resetDragState()
		selection = self.selectedNodes(layer)
		self.selectionValid = self.validSelection(selection)
		if not self.selectionValid:
			return

		self.isExtruding = True
		self.editViewController().setShadowLayer_(layer.copy())

		self.sortedSelection = self.sortSelection(layer, selection)
		firstNode = self.sortedSelection[0]
		lastNode = self.sortedSelection[-1]
		path = firstNode.parent

		if path.closed and path.nodes[0] in self.sortedSelection and path.nodes[-1] in self.sortedSelection:
			self.crossesBounds = True
			for node in path.nodes:
				if node in self.sortedSelection:
					lastNode = node
				else:
					break
			for node in reversed(path.nodes):
				if node in self.sortedSelection:
					firstNode = node
				else:
					break
		else:
			self.crossesBounds = False

		while firstNode.type == OFFCURVE:
			nextNode = self.nextNode_(firstNode)
			layer.removeObjectFromSelection_(firstNode)
			self.sortedSelection.remove(firstNode)
			firstNode = nextNode

		while lastNode.type == OFFCURVE:
			prevNode = self.prevNode_(lastNode)
			layer.removeObjectFromSelection_(lastNode)
			self.sortedSelection.remove(lastNode)
			lastNode = prevNode

		if not self.sortedSelection:
			self.selectionValid = False
			self.isExtruding = False
			self.editViewController().setShadowLayer_(None)
			return

		self.midpoint = NSPoint(
			(lastNode.x + firstNode.x) / 2.0,
			(lastNode.y + firstNode.y) / 2.0,
		)
		self.extrudeAngle = math.atan2(
			lastNode.y - firstNode.y,
			lastNode.x - firstNode.x,
		) - math.pi / 2.0
		self.pathDirection = path.direction

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
		objc.super(ExtrudeTool, self).mouseDown_(theEvent)

	def mouseDragged_(self, theEvent):
		graphicView = self.editViewController().graphicView()
		layer = graphicView.activeLayer()
		mousePosition = graphicView.getActiveLocation_(theEvent)

		if not self.isExtruding:
			self.dragStartPoint = mousePosition
			self.beginExtrusion(layer)

		if self.canExtrude and self.selectionValid:
			self.extrudeDistance = (mousePosition.x - self.dragStartPoint.x) * (self.pathDirection * -1)

			quantization = self.extrudeQuantization()
			if quantization != 0:
				self.extrudeDistance = round(self.extrudeDistance / quantization) * quantization

			for index, node in enumerate(self.sortedSelection):
				origin = self.sortedSelectionCoords[index]
				newPoint = self.translatePoint_withDistance_(origin, self.extrudeDistance)
				node.setPositionFast_(newPoint)
				layer.elementDidChange_(node)

	def mouseUp_(self, theEvent):
		if self.canExtrude and self.selectionValid:
			layer = self.editViewController().graphicView().activeLayer()
			if self.isExtruding:
				for index, node in enumerate(self.sortedSelection):
					newPos = node.positionPrecise()
					origin = self.sortedSelectionCoords[index]
					node.setPositionFast_(origin)
					node.position = newPos
			self.editViewController().setShadowLayer_(None)

		self.resetDragState()

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
