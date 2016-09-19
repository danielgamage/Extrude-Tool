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

    extrudeAngle = 0;

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
	return NO;
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

- (void)mouseDown:(NSEvent *)theEvent {
	// Called when the mouse button is clicked.
	_editViewController = [_windowController activeEditViewController];
    _editViewController.graphicView.cursor = [NSCursor resizeLeftRightCursor];
	_draggStart = [theEvent locationInWindow];

    activeLayer = [_editViewController.graphicView activeLayer];

    NSLog(@"Active Layer: %@", activeLayer);
    NSLog(@"Before Sort: %@", activeLayer.selection);

    NSArray *sortedSelection;
    sortedSelection = [activeLayer.selection sortedArrayUsingComparator:^NSComparisonResult(GSNode* a, GSNode* b) {
        NSUInteger first = [a.parent indexOfNode:(GSNode *)a];
        NSUInteger second = [b.parent indexOfNode:(GSNode *)b];
        NSNumber *one = [NSNumber numberWithInteger:first];
        NSNumber *two = [NSNumber numberWithInteger:second];
        return [one compare:two];
    }];

    NSLog(@"After Sort: %@", sortedSelection);

    GSNode *firstNode = sortedSelection[0];
    GSNode *lastNode = [sortedSelection lastObject];
    
    extrudeAngle = atan2f(lastNode.position.y - firstNode.position.y, lastNode.position.x - firstNode.position.x) - M_PI_2;

    NSLog(@"Angle: %f", extrudeAngle);

    GSPath *path = firstNode.parent;
    NSInteger firstIndex = [path indexOfNode:(GSNode *)firstNode];
    NSInteger lastIndex = [path indexOfNode:(GSNode *)lastNode];
    GSNode *firstHolder = [firstNode copy];
    GSNode *lastHolder = [lastNode copy];
//    NSLog(@"firstNode: %@", firstNode);
//    NSLog(@"lastNode : %@", lastNode);
    // Insert nodes at front and back of selection
    // Add last node THEN first node so the index remains the same
    [path insertNode:lastHolder atIndex:lastIndex + 1];
    [path insertNode:firstHolder atIndex:firstIndex];

}

- (void)mouseDragged:(NSEvent *)theEvent {
	// Called when the mouse is moved with the primary button down.
    NSPoint Loc = [theEvent locationInWindow];
    
    // Use mouse position on x axis to translate the points
    // ... should factor in zoom level and translate proportionally
    double mousePositionX = Loc.x - _draggStart.x;
    
    double distance = mousePositionX;

    NSLog(@"distance: %f", distance);

    GSLayer *layer = [_editViewController.graphicView activeLayer];

    for (GSNode *node in layer.selection) {
        NSPoint newPoint = NSMakePoint(node.positionPrecise.x + distance * cos(extrudeAngle), node.positionPrecise.y + distance * sin(extrudeAngle));
        NSLog(@"NSPoint X: %f", newPoint.x);
        NSLog(@"NSPoint Y: %f", newPoint.y);
        
        [node setPositionFast:newPoint];
    }

}

- (void)mouseUp:(NSEvent *)theEvent {
	// Called when the primary mouse button is released.
	// editViewController.graphicView.cursor = [NSCursor openHandCursor];
    // Called when the mouse is moved with the primary button down.
    NSPoint Loc = [theEvent locationInWindow];
    
    // Use mouse position on x axis to translate the points
    // ... should factor in zoom level and translate proportionally
    double mousePositionX = Loc.x - _draggStart.x;
    
    double distance = mousePositionX;
    
    NSLog(@"distance: %f", distance);
    
    GSLayer *layer = [_editViewController.graphicView activeLayer];
    
    for (GSNode *node in layer.selection) {
        NSPoint newPoint = NSMakePoint(node.positionPrecise.x + distance * cos(extrudeAngle), node.positionPrecise.y + distance * sin(extrudeAngle));
        NSLog(@"NSPoint X: %f", newPoint.x);
        NSLog(@"NSPoint Y: %f", newPoint.y);
        
        [node setPosition:newPoint];
    }
}

- (void)drawBackground {
	// Draw in the background, concerns the complete view.
}

- (void)drawForeground {
	// Draw in the foreground, concerns the complete view.
}

- (void)drawLayer:(GSLayer *)Layer atPoint:(NSPoint)aPoint asActive:(BOOL)Active attributes:(NSDictionary *)Attributes {
	// Draw anythin for this particular layer.
	[_editViewController.graphicView drawLayer:Layer atPoint:aPoint asActive:Active attributes:Attributes];
}

- (void)willActivate {
	// Called when the tool is selected by the user.
	// editViewController.graphicView.cursor = [NSCursor openHandCursor];
}

- (void)willDeactivate {}

@end
