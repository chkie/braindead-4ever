# SPDX-License-Identifier: GPL-3.0-or-later
"""The arrow textures in Braindead4Ever/Media are exactly what tools/media/arrow.py draws. Run from the
repository root:

  python3 -m unittest discover -s tools/tests -t .
"""

import math
import os
import unittest

from tools.media import arrow


class ArrowTextures(unittest.TestCase):
    def test_files_match_the_generator(self):
        for name, data in arrow.build().items():
            with open(os.path.join(arrow.MEDIA, name), "rb") as fh:
                self.assertEqual(fh.read(), data, name + " differs: run python3 -m tools.media.arrow")

    def test_tga_header_like_the_icon(self):
        data = arrow.build()["arrow.tga"]
        self.assertEqual(data[2], 2)  # uncompressed true color
        self.assertEqual((data[12] | data[13] << 8, data[14] | data[15] << 8), (128, 128))
        self.assertEqual((data[16], data[17]), (32, 8))  # 32 bit, origin bottom left, 8 alpha bits

    def test_shape_and_outline_fit_the_turning_circle(self):
        for x, y in arrow.SHAPE:
            self.assertLessEqual(math.hypot(x - 64, y - 64) + arrow.OUTLINE, 64)

    def test_tip_points_up(self):
        rows = arrow.coverage(0.0)  # top to bottom
        top = next(i for i, row in enumerate(rows) if any(row))
        self.assertLess(top, 20)
        self.assertGreater(rows[top][64], 0)  # the topmost pixel is in the middle


if __name__ == "__main__":
    unittest.main()
