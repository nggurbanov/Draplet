"""Export the approved artwork with an image-derived alpha mask.
User explicitly approved deterministic masking after two imperfect AI cutouts.
Requires Pillow, numpy and scipy (asset tooling only; never part of the app).
"""
from pathlib import Path
import numpy as np
from scipy import ndimage
from PIL import Image, ImageDraw, PngImagePlugin
from scipy.spatial import ConvexHull
root = Path(__file__).resolve().parents[1]
source = Image.open(root / 'Resources/Brand/IconSource.png').convert('RGB')
pixels = np.asarray(source).astype(np.int16)
# The tile and its artwork are warmer than the neutral presentation background.
# Recover its actual contour, rather than approximating it with a rounded rect.
warm = (pixels[:, :, 0] - pixels[:, :, 2]) > 16
labels, _ = ndimage.label(warm)
counts = np.bincount(labels.ravel()); counts[0] = 0
mask = labels == counts.argmax()
# The real tile is convex. Its warm outline survives even where the pale
# highlight joins the background; recover that contour without interior holes.
y, x = np.nonzero(mask)
points = np.column_stack((x, y))
hull = ConvexHull(points)
alpha = Image.new('L', (source.width * 4, source.height * 4))
ImageDraw.Draw(alpha).polygon([(float(px) * 4, float(py) * 4) for px, py in points[hull.vertices]], fill=255)
alpha = alpha.resize(source.size, Image.Resampling.LANCZOS)
image = source.convert('RGBA'); image.putalpha(alpha)
info = PngImagePlugin.PngInfo()
info.add_text('Description', 'Approved Draplet E presentation artwork; precise image-derived alpha export authorized by user. Source: art/draplet-e/app-icon-e-presentation.png. Interior RGB preserved.')
image.save(root / 'Resources/Brand/Draplet.png', pnginfo=info)
print('Exported clean alpha:', image.size, 'bounds:', image.getbbox())
