# Extrude Tool
Extrude Tool plugin for [Glyphs.app](https://glyphsapp.com/)

![Example GIF of Extrude Tool in use](https://media.giphy.com/media/26gJAkdmmMqWAU5d6/giphy.gif)

## Installation

### Recommended
Download _ExtrudeTool_ via the Glyphs [Plugin Manager](https://github.com/schriftgestalt/glyphs-packages). (Window > Plugin Manager)

### Alternative
1. Clone or download this repository
1. (Unzip if necessary) and open the file with the `.glyphsTool` extension.
1. Follow the "are you sure you want to install" dialogs
1. Restart glyphs

## Usage
Using the Select tool, select a group of connected nodes, switch to the Extrude tool in the top menu (`w` on the keyboard), click, and drag the cursor to the left or right to extrude the nodes inward or outward. The angle at which the nodes are extruded is equal to the angle of the perpendicular of the line that connects the first and last nodes in a selection.

### Extrude Info
By default, the tool will show an overlay with the distance extruded and the angle of the extrusion. If this interferes with your work, you can turn it off by right-clicking when the Extrude tool is selected, and toggle "Extrude Info" at the bottom of the contextual menu.

| With info | Without info |
| --- | --- |
| ![Extrude tool with info](https://github.com/danielgamage/Extrude-Tool/blob/master/images/extrude_info_with.png) | ![Extrude tool without info](https://github.com/danielgamage/Extrude-Tool/blob/master/images/extrude_info_without.png) |

### Extrusion Snapping

Alongside the Extrude Info menu item, there is an input that helps snap the distance to a more round number. This is particularly helpful if you want to extrude a distance of some multiple of, say, 8 or 10 units. By default, this is 0 (disabled).

![Extrude tool contextual menu](https://raw.githubusercontent.com/danielgamage/Extrude-Tool/master/images/contextual_menu.png)

## Roadmap
To see what's in the pipeline, check out the current issues in [projects](https://github.com/danielgamage/Extrude-Tool/projects/1).
