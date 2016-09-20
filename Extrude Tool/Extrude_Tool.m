//
//  Extrude_Tool.m
//  Extrude Tool
//
//  Created by Daniel Gamage on 9/16/16.
//    Copyright © 2016 Daniel Gamage. All rights reserved.
//

#import "Extrude_Tool.h"

@implementation Extrude_Tool

- (id)init {
	self = [super init];
	NSBundle *thisBundle = [NSBundle bundleForClass:[self class]];
	if (thisBundle) {
		// The toolbar icon:
		_toolBarIcon = [[NSImage alloc] initWithContentsOfFile:[thisBundle pathForImageResource:@"ToolbarIconTemplate"]];
		[_toolBarIcon setTemplate:YES];
	}
    canExtrude = NO;
    self.dragging = NO;
    extrudeAngle = 0;
    sortedSelectionCoords = [[NSMutableArray alloc] init];

	return self;
}

- (NSUInteger)interfaceVersion {
	// Distinguishes the API verison the plugin was built for. Return 1.
	return 1;
}

- (NSUInteger)groupID {
	// Return a number between 50 and 1000 to position the icon in the toolbar.
	return 50;
}

- (NSString *)title {
	// return the name of the tool as it will appear in the tooltip of in the toolbar.
	return @"Extrude";
}

- (NSString *)trigger {
	// Return the key that the user can press to activate the tool.
	// Please make sure to not conflict with other tools.
	return @"x";
}

- (NSInteger)tempTrigger {
	// Return a modifierMask (e.g NSAlternateKeyMask, NSCommandKeyMask ...)
	return 0;
}

- (BOOL)willSelectTempTool:(id)tempTool {
	// This is called when the user presses a modifier key (e.g. the cmd key to swith to the Select Tool).
	// Return NO to prevent the tool switching.
	return YES;
}

- (void)keyDown:(NSEvent *)theEvent {
	// Called when a key is pressed while the tool is active.
	NSLog(@"keyDown: %@", theEvent);
}

- (void)doCommandBySelector:(SEL)aSelector {
	NSLog(@"aSelector: %s", sel_getName(aSelector));
}

- (NSMenu *)defaultContextMenu {
	// Adds items to the context menu.
	NSMenu *theMenu = [[NSMenu alloc] initWithTitle:@"Contextual Menu"];
//	[theMenu addItemWithTitle:@"Foo" action:@selector(foo:) keyEquivalent:@""];
//	[theMenu addItemWithTitle:@"Bar" action:@selector(bar:) keyEquivalent:@""];
	return theMenu;
}

- (void)addMenuItemsForEvent:(NSEvent *)theEvent toMenu:(NSMenu *)theMenu {
	// Adds an item to theMenu for theEvent.
	[theMenu insertItemWithTitle:@"Wail" action:@selector(wail:) keyEquivalent:@"" atIndex:[theMenu numberOfItems] - 1];
}

- (NSPoint)translatePoint:(CGPoint)node withDistance:(double)distance {
    NSPoint newPoint = NSMakePoint(node.x + distance * cos(extrudeAngle), node.y + distance * sin(extrudeAngle));
    return newPoint;
}

- (void)mouseDragged:(NSEvent *)theEvent {
	// Called when the mouse is moved with the primary button down.

    NSPoint Loc = [_editViewController.graphicView getActiveLocation:theEvent];
    if (!_dragging) {
		// this is called the first time the user draggs. Otherwise it would insert the extra nodes if the user only clicks.
		self.dragging = YES;
		_editViewController.graphicView.cursor = [NSCursor resizeLeftRightCursor];
		_draggStart = [_editViewController.graphicView getActiveLocation:theEvent];

		layer = [_editViewController.graphicView activeLayer];

		sortedSelection = [layer.selection sortedArrayUsingComparator:^NSComparisonResult(GSNode* a, GSNode* b) {
			NSUInteger first = [layer indexOfPath:a.parent];
			NSUInteger second = [layer indexOfPath:b.parent];
			if (first > second) { return NSOrderedDescending; }
			if (first < second) { return NSOrderedAscending; }

			first = [a.parent indexOfNode:a];
			second = [b.parent indexOfNode:b];
			if (first > second) { return NSOrderedDescending; }
			if (first < second) { return NSOrderedAscending; }
			return NSOrderedSame;
		}];

        for (GSNode *node in sortedSelection) {
            [sortedSelectionCoords addObject:[NSValue valueWithPoint:node.positionPrecise]];
        }

		GSNode *firstNode = sortedSelection[0];
		GSNode *lastNode = [sortedSelection lastObject];

		extrudeAngle = atan2f(lastNode.position.y - firstNode.position.y, lastNode.position.x - firstNode.position.x) - M_PI_2;

		GSPath *path = firstNode.parent;
		NSInteger firstIndex = [path indexOfNode:firstNode];
		NSInteger lastIndex = [path indexOfNode:lastNode] + 1;
		GSNode *firstHolder = [firstNode copy];
		GSNode *lastHolder = [lastNode copy];

    // Disallow Extrusion if first and last nodes in selection are OFFCURVE
    if ([path nodeAtIndex:firstIndex].type != OFFCURVE && [path nodeAtIndex:lastIndex - 1].type != OFFCURVE) {
        canExtrude = YES;
    } else {
        canExtrude = NO;
    }

    if (canExtrude == YES) {
        // Insert nodes at front and back of selection
        // Add last node THEN first node so the index remains the same
        [path insertNode:lastHolder atIndex:lastIndex];
        [path insertNode:firstHolder atIndex:firstIndex];

        [[path nodeAtIndex:firstIndex] setConnection:SHARP];
        [[path nodeAtIndex:firstIndex + 1] setConnection:SHARP];
        [[path nodeAtIndex:firstIndex + 1] setType:LINE];

        [[path nodeAtIndex:lastIndex] setConnection:SHARP];
        [[path nodeAtIndex:lastIndex + 1] setConnection:SHARP];
        [[path nodeAtIndex:lastIndex + 1] setType:LINE];
    }
  }

  if (canExtrude == YES) {

    // Use mouse position on x axis to translate the points
    // ... should factor in zoom level and translate proportionally
    double distance = (Loc.x - _draggStart.x) / _editViewController.graphicView.scale;

    NSInteger index = 0;
    for (GSNode *node in sortedSelection) {
        CGPoint origin = [sortedSelectionCoords[index] pointValue];
        NSPoint newPoint = [self translatePoint:origin withDistance:distance];
        [node setPositionFast:newPoint];
        [layer elementDidChange:node];
        index++;
    }
  }

}

- (void)mouseUp:(NSEvent *)theEvent {
	// Called when the primary mouse button is released.
    if (canExtrude == YES) {

      if (_dragging) {
          NSInteger index = 0;
          for (GSNode *node in sortedSelection) {
              CGPoint newPos = node.positionPrecise;
              CGPoint origin = [sortedSelectionCoords[index] pointValue];
              [node setPositionFast:origin];
              [node setPosition:newPos];
              index++;
          }
      }
    }

    self.dragging = NO;

    // empty coordinate cache
    [sortedSelectionCoords removeAllObjects];
}

- (void)drawBackground {
	// Draw in the background, concerns the complete view.
}

- (void)drawForeground {
	// Draw in the foreground, concerns the complete view.
}

- (void)drawLayer:(GSLayer *)Layer atPoint:(NSPoint)aPoint asActive:(BOOL)Active attributes:(NSDictionary *)Attributes {
	// Draw anythin for this particular layer.
//    [_editViewController.graphicView drawLayer:Layer atPoint:aPoint asActive:true attributes:Attributes];
    [super drawLayer:Layer atPoint:aPoint asActive:Active attributes:Attributes];
}

- (void)willActivate {
	// Called when the tool is selected by the user.
	// editViewController.graphicView.cursor = [NSCursor openHandCursor];
}

- (void)willDeactivate {}

@end
