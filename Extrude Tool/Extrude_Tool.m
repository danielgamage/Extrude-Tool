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

            bgPath = [layer bezierPath];

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
            double distance = mousePosition.x - _draggStart.x;

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
        // empty coordinate cache
        [sortedSelectionCoords removeAllObjects];
        bgPath = NULL;
    }

    self.dragging = NO;
}

- (void)drawBackground {
    // Draw in the background, concerns the complete view.
   if (bgPath) {
       NSRect bounds = [layer bounds];
       NSLog(@"%@", CGRectCreateDictionaryRepresentation(bounds));
       NSRect pathBounds = [bgPath bounds];
       NSLog(@"%@", CGRectCreateDictionaryRepresentation(pathBounds));

       [[NSColor lightGrayColor] set];
       [bgPath setLineWidth: 1];
       [bgPath stroke];
   }
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
