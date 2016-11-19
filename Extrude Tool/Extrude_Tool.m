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
    extrudeInfo = YES;
    canExtrude = NO;
    selectionValid = NO;
    self.dragging = NO;
    extrudeAngle = 0;
    extrudeDistance = 0;
    extrudeQuantization = 0;
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
    return @"w";
}

- (void)toggleHUD {
    extrudeInfo = extrudeInfo ? NO : YES;
}

- (void)addMenuItemsForEvent:(NSEvent *)theEvent toMenu:(NSMenu *)theMenu {
    // Adds an item to theMenu for theEvent.
    NSMenuItem *extrudeInfoItem = [[NSMenuItem alloc] initWithTitle:@"Extrude Info" action:@selector(toggleHUD) keyEquivalent:@""];
    NSMenuItem *extrudeSliderItem = [[NSMenuItem alloc] initWithTitle:@"Extrude Snapping" action:nil keyEquivalent:@""];

    // Make view for Quantization slider
    CGRect  viewRect = CGRectMake(0, 0, 184, 48);
    NSView* sliderView = [[NSView alloc] initWithFrame:viewRect];
    NSInteger margin = 20;

    // Label above
    CGRect labelRect = CGRectMake(margin, 22, sliderView.frame.size.width - margin, 24);
    NSTextField *labelField = [[NSTextField alloc] initWithFrame:labelRect];
    [labelField setStringValue:@"Extrusion Snapping"];
    labelField.font = [NSFont menuFontOfSize:11];
    [labelField setBezeled:NO];
    [labelField setDrawsBackground:NO];
    [labelField setEditable:NO];
    [labelField setSelectable:NO];
    [labelField setTextColor:[NSColor darkGrayColor]];
    [sliderView addSubview:labelField];

    // Slider input
    CGRect sliderRect = NSMakeRect(margin, 0, 121, 24);
    NSSlider *slider = [[NSSlider alloc] initWithFrame:sliderRect];
    slider.doubleValue = (double)extrudeQuantization;
    slider.minValue = 0.00;
    slider.maxValue = 10.00;
    slider.action = @selector(updateQuantization:);
    slider.continuous = YES;
    slider.numberOfTickMarks = 11;
    slider.allowsTickMarkValuesOnly = YES;
    slider.target = self;
    [sliderView addSubview:slider];

    // Slider value
    CGRect valueRect = CGRectMake(slider.frame.origin.x + slider.frame.size.width, 0, viewRect.size.width - slider.frame.origin.x - slider.frame.size.width - 15, 26);
    valueField = [[NSTextField alloc] initWithFrame:valueRect];
    [valueField setAlignment:NSTextAlignmentRight];
    [valueField setStringValue:[self updateQuantizationString]];
    [valueField setBezeled:NO];
    [valueField setDrawsBackground:NO];
    [valueField setEditable:NO];
    [valueField setSelectable:NO];
    [sliderView addSubview:valueField];

    (extrudeInfo) ? [extrudeInfoItem setState:NSOnState] : [extrudeInfoItem setState:NSOffState];

    [extrudeSliderItem setView: sliderView];

    [theMenu addItem:[NSMenuItem separatorItem]];
    [theMenu addItem:extrudeInfoItem];
    [theMenu addItem:extrudeSliderItem];
}

- (void)updateQuantization:(id)sender {
    NSSlider *slider = (NSSlider*)sender;
    extrudeQuantization = slider.doubleValue;
    extrudeQuantizationString = [self updateQuantizationString];
    [valueField setStringValue:extrudeQuantizationString];
}
- (NSString *)updateQuantizationString {
    return (extrudeQuantization == 0) ? @"Off" : [NSString stringWithFormat:@"%i", extrudeQuantization];
}

- (NSPoint)translatePoint:(CGPoint)node withDistance:(double)distance {
    NSPoint newPoint = NSMakePoint(node.x + distance * cos(extrudeAngle), node.y + distance * sin(extrudeAngle));
    return newPoint;
}

- (bool)validSelection:(NSMutableOrderedSet *)selection {
    if (selection.count) {
        GSNode *node = selection[0];
        GSPath *path = node.parent;
        if (path.closed) {
            return (selection.count < path.nodes.count);
        } else {
            return YES;
        }
    } else {
        return NO;
    }
}

- (void)mouseDragged:(NSEvent *)theEvent {
    // Called when the mouse is moved with the primary button down.

    layer = [_editViewController.graphicView activeLayer];

    mousePosition = [_editViewController.graphicView getActiveLocation:theEvent];
    if (!_dragging) {
        // Run the first time the user draggs. Otherwise it would insert the extra nodes if the user only clicks.
        // layer.selection.count: Ensure there is a selection before running operations on the selection
        selectionValid = [self validSelection:layer.selection];

        if (selectionValid) {
            self.dragging = YES;
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
            if (path.closed && [sortedSelection containsObject:[path.nodes firstObject]] && [sortedSelection containsObject:[path.nodes lastObject]]) {
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

            pathDirection = path.direction;

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
    }

    if (canExtrude && selectionValid) {

        // Use mouse position on x axis to translate the points
        // should counter-act path direction
        extrudeDistance = (mousePosition.x - _draggStart.x) * (pathDirection * -1);

        // Quantize to nearest multiple of quantize value
        if (extrudeQuantization != 0) {
            extrudeDistance = round(extrudeDistance / extrudeQuantization) * extrudeQuantization;
        }

        NSInteger index = 0;
        for (GSNode *node in sortedSelection) {
            CGPoint origin = [sortedSelectionCoords[index] pointValue];
            NSPoint newPoint = [self translatePoint:origin withDistance:extrudeDistance];
            // setPositionFast so not EVERY update is logged in history.
            // force paint in elementDidChange because setPositionFast doesn't notify
            [node setPositionFast:newPoint];
            [layer elementDidChange:node];
            index++;
        }
    }
}

- (void)mouseUp:(NSEvent *)theEvent {
    // Called when the primary mouse button is released.

    if (canExtrude && selectionValid) {
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

- (void)drawForegroundForLayer:(GSLayer*)Layer {
    // Only show if option to show Extrude HUD is checked
    if (_dragging && extrudeInfo) {
        // Adapted from https://github.com/Mark2Mark/Show-Distance-And-Angle-Of-Nodes
        float scale = [_editViewController.graphicView scale];

        // Translate & scale midpoint
        NSPoint midpointWithDistance = [self translatePoint:midpoint withDistance:extrudeDistance];
        NSPoint midpointTranslated = NSMakePoint(midpointWithDistance.x, midpointWithDistance.y);

        // Define text
        NSDictionary *textAttributes = [NSDictionary dictionaryWithObjectsAndKeys:[NSFont labelFontOfSize:(10 / scale)], NSFontAttributeName,[NSColor whiteColor], NSForegroundColorAttributeName, nil];
        NSString *line1 = [NSString stringWithFormat:@"%.2f", extrudeDistance];
        NSString *line2 = [NSString stringWithFormat:@"%.2f°", extrudeAngle * 180 / M_PI ];
        NSString *text = [NSString stringWithFormat:@"%@\n%@", line1, line2];
        NSAttributedString *displayText = [[NSAttributedString alloc] initWithString:text attributes:textAttributes];
        // Get greater of the two line letter-counts
        int textLength = MAX((int)[line1 length], (int)[line2 length]);

        int rectWidth = (textLength * 10 - 10) / scale;
        int rectHeight = (40) / scale;

        NSPoint midpointAdjusted = NSMakePoint(midpointTranslated.x - rectWidth / 2, midpointTranslated.y - rectHeight / 2);

        // Draw rectangle bg
        NSBezierPath *myPath = [[NSBezierPath alloc] init];
        [[NSColor colorWithCalibratedRed:0 green:.6 blue:1 alpha:0.75] set];
        NSRect dirtyRect = NSMakeRect(midpointAdjusted.x, midpointAdjusted.y, rectWidth, rectHeight);
        [myPath appendBezierPathWithRoundedRect:dirtyRect xRadius: 8/scale yRadius: 8/scale];
        [myPath appendBezierPath:myPath];
        [myPath fill];

        // Draw text
        [displayText drawAtPoint:NSMakePoint(midpointAdjusted.x + 8 / scale, midpointAdjusted.y + 6 / scale)];
    }

}

- (void)drawLayer:(GSLayer *)Layer atPoint:(NSPoint)aPoint asActive:(BOOL)Active attributes:(NSDictionary *)Attributes {
    // Draw anythin for this particular layer.
    [super drawLayer:Layer atPoint:aPoint asActive:Active attributes:Attributes];
}

- (void)willActivate {
    // Called when the tool is selected by the user.
    _editViewController.graphicView.cursor = [NSCursor resizeLeftRightCursor];
}

- (void)willDeactivate {}

@end
