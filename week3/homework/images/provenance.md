# Snake Homework Data Provenance

All three sample images are photos fetched directly with `curl` from
`live.staticflickr.com` and stored verbatim (no re-encoding). All three are
licensed CC BY 2.0 (https://creativecommons.org/licenses/by/2.0/).

## `images/image1.jpg`

"Pumpkin #2" by taylor.a
(https://www.flickr.com/photos/profilerehab/4016464532/)

Source URL: https://live.staticflickr.com/3/2777/4016464532_2ec9a87746_z.jpg

A pumpkin on a plain white background. The easy case: high contrast,
a mostly-convex near-round silhouette (the stem is the only real
protrusion), so a strong initial contour should already sit close to the
true boundary.

## `images/image2.jpg`

"1k26-circles-withtray" by Rubbermaid Products
(https://www.flickr.com/photos/rubbermaid/7041679635/)

Source URL: https://live.staticflickr.com/8/7213/7041679635_073cc2e9ff_z.jpg

A patterned storage box on a plain white background, shown at an angle so
its outline is a hexagon rather than a simple rectangle. Medium: the
silhouette is still convex, but the box's own surface pattern (a dense
circle motif) produces internal edges nearly as strong as the true outer
boundary against the white background.

## `images/image3.jpg`

"Vandaag lancering nieuwe dienst www.clowds.nl #in" by Detlef La Grand
(https://www.flickr.com/photos/detleflagrand/6674250493/)

Source URL: https://live.staticflickr.com/8/7019/6674250493_e6caa614e4_z.jpg

A briefcase (with an iPad screen printed on its front flap) on a plain
white background. Hardest of the three: the carrying handle forms a real
loop with background visible through the gap, so the silhouette is
genuinely non-convex (a convex hull will bridge over that gap rather than
follow it), and the printed screen graphic adds internal high-contrast
edges competing with the true outline.

## License

CC BY 2.0 requires attribution, which is given above (author, title, and
source URL for each photo). No separate license text file is vendored since
CC BY 2.0 is the license of the individual photo, not a piece of software.
