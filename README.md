# imaging
An image / bumpmap importer mod for Minetest

Developed and tested on Minetest 0.4.16 - try in other versions at your own risk :)

WIP mod forum discussion: https://forum.minetest.net/viewtopic.php?f=9&t=20411

**Table of Contents**
- [Dependencies and Licensing](#dependencies-and-licensing)
- [Features](#features)
- [Recipe](#recipe)
- [Converter](#converter)
  - [Converter options](#converter-options)
- [Importer](#importer)
  - [Importer options](#importer-options)
  - [Bump mapping](#bump-mapping)
- [Imaging data format](#imaging-data-format)
- [Custom palettes](#custom-palettes)

## Dependencies and Licensing

This mod depends on the [[matrix]](https://github.com/entuland/lua-matrix) mod.

The code is licensed under the [MIT](/LICENSE) license.

Except otherwise specified, all media is licensed as [CC BY SA 3.0](http://creativecommons.org/licenses/by-sa/3.0/)

[The Minetest Logo screenshot](/screenshots/minetest-logo.png) is [CC BY SA 3.0 Minetest team](https://github.com/minetest/minetest/blob/master/LICENSE.txt)

[The sardinian girl screenshot](/screenshots/sardinian-girl.png) is [CC BY 2.0 Cristiano Cani](https://www.flickr.com/photos/cristianocani/2457125478/)

## Features

This mod allows to convert arbitrary images and build them in a Minetest world using up to 256 different colors, with some additional options such as bumpmapping.

This mod is composed by two parts:

- `the converter` is an HTML page to be run in a browser to convert images into `imaging` codes according to a given palette
- `the importer` is a block called `imaging:canvas` placed in the world to define the bottom-center of the imported image and its orientation

## Recipe
The recipe can be customized altering the file `custom.recipes.lua`, created in the mod's folder on first run and never overwritten.

    W = any wood planks
    B = mese block

    WWW
    W W
    WBW

![Crafting](/screenshots/canvas-recipe.png)

## Converter

To launch the converter run the `/html/index.html` file contained in the mod folder, you should see something like this:

![Converter](/screenshots/converter.png)

There you can load an image by clicking on the file selector marked in yellow in the *Image Input* box (you can also drag files on that file selector), then alter the conversion params and hit the `Generate imaging data` button, obtaining something like this:

![Converter Output](/screenshots/converter-output.png)

Clicking in the yellow *Output* textarea all the text will be selected: copy it into the clipboard and keep it handy to be imported in the game.

### Converter options

- The three `Palette` buttons load one of the three default palettes; you can use any custom palette as long as it has exactly 256 pixels; in order to use such a palette you'll also need to add it to the mod `/textures` folder and restart the world
- The `Dithering` checkbox adds [Floyd-Steinberg dithering](https://en.wikipedia.org/wiki/Floyd%E2%80%93Steinberg_dithering) to the resulting image.
- The `Minimum opacity` number determines what pixels will be considered and which ones will be ignored (the default `255` value will ignore any pixel that is not fully opaque, lower this value to use partially-transparent pixels)

## Importer

This is how the `imaging:canvas` importer looks like:

![Imaging Canvas](/screenshots/imaging-canvas.png)

You can freely rotate it to decide in what direction the image will be imported.

Once you right click it you'll see the default import interface:

![Default Interface](/screenshots/default-interface.png)

There you need to paste the `imaging data` you copied from the `converter` and click on `Build`, obtaining something like this:

![Minetest Logo](/screenshots/minetest-logo.png)

You can import pretty large images as well, this is the result of converting a portion of this image using the `sepia` palette:
https://www.flickr.com/photos/cristianocani/2457125478/

![Sardinian girl](/screenshots/sardinian-girl.png)

### Importer options

- The `imaging data` only contains the info about the palette index for each pixel, for that reason it is necessary to choose the appropriate palette in the dropdown of the importer as well (or not, you can also use a different palette which may result in some weird "fake colors" effect).
- `Build as`: if you select this option the image will be built using the chosen nodes - you can also build as `air` to get rid of an image you previously built.
- `Bump value`: if you set any positive value in this field, the palette index will be used to "bump" the nodes out of the image; for example, if you set the bump value to `10` then pixels with index `255` will be 10 nodes away from their original position in the plane of the image, indices around `127` will be about 5 nodes away and so forth.

(note: in a palette such as the `grayscale` one, black is at index `0` and white is at index `255`, with gradients of gray getting brighter as the index increases)

### Bump mapping

For example, you can draw an elevation map with an airbrush and convert it like this:
![Converter bump](/screenshots/converter-bump.png)

Then you can import it with these params:
![Bump build](/screenshots/bump-build.png)

And finally obtain something like this:
![Bump result](/screenshots/bump-result.png)

## Imaging Data Format

The `imaging data` is a run-length textual format defining the image in top-down, left-right order with these specifics:

- the data is a space separated series of `chunks`
- the first chunk is the width of the image
- the second chunk is the height of the image
- any subsequent chunk follows this format `index:count` where
  - `index` can be missing (those nodes will be completely ignored), for example `:200` means "skip 200 nodes"
  - `count` can be missing (meaning that the count will be `1`), for instance `0:` using the grayscale palette means "one black node" and `255:3` means "three white nodes"

All the above means that you can use the `imaging:canvas` to get rid of any image even without having the original code - it's enough that you guess the sizes and build them as `air` - for instance to remove a 32 x 48 image you would paste a code like this `32 48 0:1536` cause `32 * 48 == 1536`; notice that you _need_ to specify it as `0:1536`, cause `:1536` alone means "skip 1536 nodes" and those nodes will not be altered in the world regardless if you chose to build as `air` or `default:dirt` or anything else.

## Custom palettes

Custom palettes are PNG images with exactly 256 pixels (say, 16x16 or 32x8) that must be placed into the `/textures` folder and named exactly as `palette-customname.png` (where "customname" can be anything you want).

Upon world restart the mod will find that custom palette and will add it to the palettes' dropdown in the `imaging:canvas` interface.

Those custom palettes will *not* be picked up automatically by the HTML `converter`, though: you'll need to drag/open such palettes manually in the browser's interface.
