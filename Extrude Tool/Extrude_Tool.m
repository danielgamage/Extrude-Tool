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
    return 20;
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

- (void)toggleHUD {
    hudActive = hudActive ? NO : YES;
    NSLog(@"%hhd", hudActive);
}

- (void)addMenuItemsForEvent:(NSEvent *)theEvent toMenu:(NSMenu *)theMenu {
    // Adds an item to theMenu for theEvent.
    SEL toggleHUD = NSSelectorFromString(@"toggleHUD");
    [theMenu insertItemWithTitle:@"Toggle HUD" action:@selector(toggleHUD) keyEquivalent:@"" atIndex:[theMenu numberOfItems] - 1];
}

- (NSPoint)translatePoint:(CGPoint)node withDistance:(double)distance {
    NSPoint newPoint = NSMakePoint(node.x + distance * cos(extrudeAngle), node.y + distance * sin(extrudeAngle));
    return newPoint;
}

- (bool)validSelection:(NSMutableOrderedSet *)selection {
    if (selection.count) {
        GSNode *node = selection[0];
        GSPath *path = node.parent;
        return (path.nodes.count != selection.count);
    } else {
        return NO;
    }
}

- (void)mouseDragged:(NSEvent *)theEvent {
    // Called when the mouse is moved with the primary button down.

    layer = [_editViewController.graphicView activeLayer];

    mousePosition = [_editViewController.graphicView getActiveLocation:theEvent];

    if ([self validSelection:layer.selection]) {
        if (!_dragging) {
            // Run the first time the user draggs. Otherwise it would insert the extra nodes if the user only clicks.
            // layer.selection.count: Ensure there is a selection before running operations on the selection
            self.dragging = YES;
            _editViewController.graphicView.cursor = [NSCursor resizeLeftRightCursor];
            _draggStart = [_editViewController.graphicView getActiveLocation:theEvent];

            // Set background before manipulating activeLayer
            _editViewController.shadowLayer = [layer copy];

            sortedSelection = [layer.selection sortedArrayUsingComparator:^NSComparisonResult(GSNode* a, GSNode* b) {
                // Sort by path parent
                NSUInteger first = [layer indexOfPath:a.parent];
                NSUInteger second = [layer indexOfPath:b.parent];
                if (first > second) { return NSOrderedDescending; }
                if (first < second) { return NSOrderedAscending; }

                // Then sort by node index
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
            GSPath *path = firstNode.parent;

            // If first & last nodes are selected, the selection crosses bounds of the array
            if ([sortedSelection containsObject:[path.nodes firstObject]] && [sortedSelection containsObject:[path.nodes lastObject]]) {
                crossesBounds = YES;

                // Reassign first and last nodes accordingly
                for (NSUInteger i=0; [sortedSelection containsObject:path.nodes[i]]; i++) {
                    lastNode = path.nodes[i]; }
                for (NSUInteger d=path.nodes.count - 1; [sortedSelection containsObject:path.nodes[d]]; d--) {
                    firstNode = path.nodes[d]; }
            } else {
                crossesBounds = NO;
            }

            // Get midpoint between first and last nodes
            midpoint = NSMakePoint(((lastNode.position.x + firstNode.position.x) / 2), ((lastNode.position.y + firstNode.position.y) / 2));

            // Get angle at which to extrude
            extrudeAngle = atan2f(lastNode.position.y - firstNode.position.y, lastNode.position.x - firstNode.position.x) - M_PI_2;

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
                int offset = crossesBounds ? 1 : 0;

                // Insert nodes at front and back of selection
                // shift the last index +1 because a node was inserted before it,
                // or don't if the selection crosses bounds (the first / last nodes are effectively flipped)
                [path insertNode:firstHolder atIndex:firstIndex];
                [path insertNode:lastHolder atIndex:lastIndex + 1 - offset];

                [[path nodeAtIndex:firstIndex + offset] setConnection:SHARP];
                [[path nodeAtIndex:firstIndex + offset + 1] setConnection:SHARP];
                [[path nodeAtIndex:firstIndex + offset + 1] setType:LINE];

                [[path nodeAtIndex:lastIndex - offset] setConnection:SHARP];
                [[path nodeAtIndex:lastIndex - offset + 1] setConnection:SHARP];
                [[path nodeAtIndex:lastIndex - offset + 1] setType:LINE];
            }

        }

        if (canExtrude == YES) {

            // Use mouse position on x axis to translate the points
            // ... should factor in zoom level and translate proportionally
            distance = mousePosition.x - _draggStart.x;

            NSInteger index = 0;
            for (GSNode *node in sortedSelection) {
                CGPoint origin = [sortedSelectionCoords[index] pointValue];
                NSPoint newPoint = [self translatePoint:origin withDistance:distance];
                // setPositionFast so not EVERY update is logged in history.
                // force paint in elementDidChange because setPositionFast doesn't notify
                [node setPositionFast:newPoint];
                [layer elementDidChange:node];
                index++;
            }
        }
    }
}

- (void)mouseUp:(NSEvent *)theEvent {
    // Called when the primary mouse button is released.

    if (canExtrude == YES && [self validSelection:layer.selection]) {
        if (_dragging) {
            NSInteger index = 0;
            for (GSNode *node in sortedSelection) {
                CGPoint newPos = node.positionPrecise;
                CGPoint origin = [sortedSelectionCoords[index] pointValue];
                // revert to origin first so that history log shows move from point@origin to point@newPos, instead of form wherever mouseDragged left off
                [node setPositionFast:origin];
                [node setPosition:newPos];
                index++;
            }
        }
        // Empty coordinate cache
        [sortedSelectionCoords removeAllObjects];
        // Remove background contents
        _editViewController.shadowLayer = NULL;
    }
    self.dragging = NO;
}

- (void)drawForeground {
    // Draw in the foreground, concerns the complete view.

    // Only show if option to show Extrude HUD is checked
    if (_dragging && hudActive) {
        // Adapted from https://github.com/Mark2Mark/Show-Distance-And-Angle-Of-Nodes
        float scale = [_editViewController.graphicView scale];

        // Translate & scale midpoint
        NSPoint midpointWithDistance = [self translatePoint:midpoint withDistance:distance];
        NSPoint midpointTranslated = NSMakePoint(((midpointWithDistance.x) * scale), ((midpointWithDistance.y - layer.glyphMetrics.ascender) * scale));

        // Define text
        NSDictionary *textAttributes = [NSDictionary dictionaryWithObjectsAndKeys:[NSFont labelFontOfSize:10], NSFontAttributeName,[NSColor whiteColor], NSForegroundColorAttributeName, nil];
        NSString *line1 = [NSString stringWithFormat:@"%.2f", distance];
        NSString *line2 = [NSString stringWithFormat:@"%.2f°", extrudeAngle * 180 / M_PI ];
        NSString *text = [NSString stringWithFormat:@"%@\n%@", line1, line2];
        NSAttributedString *displayText = [[NSAttributedString alloc] initWithString:text attributes:textAttributes];
        // Get greater of the two line letter-counts
        int textLength = MAX((int)[line1 length], (int)[line2 length]);

        int rectWidth = textLength * 10 - 10;
        int rectHeight = 40;

        NSPoint midpointAdjusted = NSMakePoint(midpointTranslated.x - rectWidth / 2, midpointTranslated.y - rectHeight / 2);

        // Draw rectangle bg
        NSBezierPath *myPath = [[NSBezierPath alloc] init];
        [[NSColor colorWithCalibratedRed:0 green:.6 blue:1 alpha:0.75] set];
        NSRect dirtyRect = NSMakeRect(midpointAdjusted.x, midpointAdjusted.y, rectWidth, rectHeight);
        [myPath appendBezierPathWithRoundedRect:dirtyRect xRadius: 8 yRadius: 8];
        [myPath appendBezierPath:myPath];
        [myPath fill];



        // Draw text
        [displayText drawAtPoint:NSMakePoint(midpointAdjusted.x + 8, midpointAdjusted.y + 6)];
    }

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
