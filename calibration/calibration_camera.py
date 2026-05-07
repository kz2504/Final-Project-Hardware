import cv2 as cv
import numpy as np
import glob
import os


# Change this if your chessboard is different.
# This is the number of INTERNAL corners, not squares.
CHESSBOARD_SIZE = (7, 6)

# Optional: actual square size in mm, cm, inches, etc.
# If unknown, leave as 1.0. The intrinsic matrix is still usable.
SQUARE_SIZE = 1.0

IMAGE_FOLDER = "calibration_images"
OUTPUT_FILE = "camera_intrinsics.npz"


def calibrate_camera():
    criteria = (
        cv.TERM_CRITERIA_EPS + cv.TERM_CRITERIA_MAX_ITER,
        30,
        0.001,
    )

    objp = np.zeros((CHESSBOARD_SIZE[0] * CHESSBOARD_SIZE[1], 3), np.float32)
    objp[:, :2] = (
        np.mgrid[0:CHESSBOARD_SIZE[0], 0:CHESSBOARD_SIZE[1]]
        .T
        .reshape(-1, 2)
    )

    objp *= SQUARE_SIZE

    objpoints = []
    imgpoints = []

    image_paths = glob.glob(os.path.join(IMAGE_FOLDER, "*.jpg"))
    image_paths += glob.glob(os.path.join(IMAGE_FOLDER, "*.png"))

    if not image_paths:
        raise RuntimeError(f"No images found in folder: {IMAGE_FOLDER}")

    image_size = None
    good_images = 0

    for path in image_paths:
        img = cv.imread(path)

        if img is None:
            print(f"Skipping unreadable image: {path}")
            continue

        gray = cv.cvtColor(img, cv.COLOR_BGR2GRAY)
        image_size = gray.shape[::-1]

        found, corners = cv.findChessboardCorners(gray, CHESSBOARD_SIZE, None)

        if found:
            corners_refined = cv.cornerSubPix(
                gray,
                corners,
                (11, 11),
                (-1, -1),
                criteria,
            )

            objpoints.append(objp)
            imgpoints.append(corners_refined)
            good_images += 1

            print(f"Found corners: {path}")
        else:
            print(f"No corners found: {path}")

    if good_images < 10:
        print(f"Warning: only {good_images} good images found. 10+ is better.")

    if good_images == 0:
        raise RuntimeError("No usable chessboard images found.")

    ret, camera_matrix, dist_coeffs, rvecs, tvecs = cv.calibrateCamera(
        objpoints,
        imgpoints,
        image_size,
        None,
        None,
    )

    print("\nCalibration RMS error:")
    print(ret)

    print("\nIntrinsic camera matrix:")
    print(camera_matrix)

    print("\nDistortion coefficients:")
    print(dist_coeffs)

    np.savez(
        OUTPUT_FILE,
        camera_matrix=camera_matrix,
        dist_coeffs=dist_coeffs,
        rvecs=rvecs,
        tvecs=tvecs,
        rms_error=ret,
        image_size=image_size,
    )

    print(f"\nSaved calibration to: {OUTPUT_FILE}")

    return camera_matrix, dist_coeffs


if __name__ == "__main__":
    calibrate_camera()
