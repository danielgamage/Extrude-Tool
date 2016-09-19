//
//  Extrude_Tool.h
//  Extrude Tool
//
//  Created by Daniel Gamage on 9/16/16.
//  Copyright © 2016 Daniel Gamage. All rights reserved.
//

#import <Cocoa/Cocoa.h>
#import <GlyphsCore/GlyphsToolDrawProtocol.h>
#import <GlyphsCore/GlyphsToolEventProtocol.h>
#import <GlyphsCore/GlyphsPathPlugin.h>
#import <GlyphsCore/GSLayer.h>
#import <GlyphsCore/GSPath.h>
#import <GlyphsCore/GSNode.h>

@interface Extrude_Tool : GlyphsPathPlugin {
    double extrudeAngle;
}

@end
