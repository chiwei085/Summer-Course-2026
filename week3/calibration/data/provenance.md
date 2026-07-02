# Calibration Data Provenance

This lab uses the chessboard images `left01.jpg` through `left14.jpg` from the
OpenCV sample data repository:

https://github.com/opencv/opencv/tree/4.x/samples/data

OpenCV is licensed under Apache License 2.0. A copy of that license is stored in
`OPENCV_LICENSE.txt`.

The C++ lab does not link against OpenCV. OpenCV was used once, offline, to
extract sub-pixel chessboard corner observations into `observations.csv`.

Corner extraction command used while preparing this dataset:

```bash
python3 - <<'PY'
from pathlib import Path
import csv
import cv2

root = Path('data')
images = sorted((root / 'images').glob('left*.jpg'))
pattern = (9, 6)
criteria = (cv2.TERM_CRITERIA_EPS + cv2.TERM_CRITERIA_MAX_ITER, 30, 0.001)
rows = []
for image_path in images:
    image = cv2.imread(str(image_path), cv2.IMREAD_GRAYSCALE)
    ok, corners = cv2.findChessboardCorners(image, pattern, None)
    if not ok:
        raise SystemExit(f'failed to find corners in {image_path}')
    corners = cv2.cornerSubPix(image, corners, (11, 11), (-1, -1), criteria)
    for idx, corner in enumerate(corners.reshape(-1, 2)):
        rows.append({
            'image': image_path.name,
            'row': idx // pattern[0],
            'col': idx % pattern[0],
            'x_px': f'{float(corner[0]):.6f}',
            'y_px': f'{float(corner[1]):.6f}',
        })

with (root / 'observations.csv').open('w', newline='') as fh:
    writer = csv.DictWriter(fh, fieldnames=['image', 'row', 'col', 'x_px', 'y_px'])
    writer.writeheader()
    writer.writerows(rows)
PY
```

Do not edit `observations.csv` by hand. If the image set or board definition
changes, regenerate the observations from the source images and update this
file with the exact command used.
