import json

import matplotlib.pyplot as plt
import numpy as np
from PIL import Image, ImageDraw, ImageFont


# Read the OSRM response
with open("./osrm-zuri.json", "r") as file:
    data = json.load(file)

coordinates = data["routes"][0]["geometry"]["coordinates"]
waypoints = data.get("waypoints", [])

# Read the ASCII grid file
asc_path = "shadows_zurich_city.asc"
with open(asc_path, "r") as f:
    # Read header
    header = {}
    for _ in range(6):
        line = f.readline().strip()
        key, value = line.split()
        header[key.lower()] = float(value)

    ncols = int(header["ncols"])
    nrows = int(header["nrows"])
    xllcorner = header["xllcorner"]
    yllcorner = header["yllcorner"]
    cellsize = header["cellsize"]
    nodata = header["nodata_value"]

    # Read data
    data_vals = np.loadtxt(f, dtype=float)

# data_vals should now be a 2D array with shape (nrows, ncols), top row first.
# If needed, confirm that the top line in the file corresponds to the northernmost row.

# Replace nodata values with something visible or handle them (e.g. mask them)
data_masked = np.ma.masked_equal(data_vals, nodata)

# Normalize data for visualization (optional)
# Here we just stretch the values to 0-255 for display
# If your data is already in a suitable range, adjust as needed.
valid_data = data_masked.compressed()
if valid_data.size > 0:
    min_val = valid_data.min()
    max_val = valid_data.max()
    # Simple normalization
    img_data = (data_masked - min_val) / (max_val - min_val) * 255
    # Fill nodata with 0 (black) for visualization
    img_data = img_data.filled(0)
else:
    # If all data is nodata, just create a blank image
    img_data = np.zeros((nrows, ncols), dtype=np.uint8)

img_data = img_data.astype(np.uint8)

# Create an image from the array (grayscale)
base_image = Image.fromarray(img_data, mode="L").convert("RGBA")


# Define a function to convert lat/lon to pixel coordinates
def lat_lon_to_pixel(lat, lon, xllcorner, yllcorner, cellsize, nrows):
    # The top-left pixel (0,0) in image corresponds to:
    # geographic coordinate: (xllcorner, yllcorner + nrows * cellsize)
    #
    # Pixel coordinates:
    # x_pixel = (longitude - xllcorner) / cellsize
    # y_pixel = ((yllcorner + nrows*cellsize) - latitude) / cellsize
    #
    # Ensure indices are integers and within bounds.

    x_pixel = int((lon - xllcorner) / cellsize)
    y_pixel = int(((yllcorner + nrows * cellsize) - lat) / cellsize)
    return x_pixel, y_pixel


# Create an overlay for drawing
overlay_image = Image.new("RGBA", base_image.size, (255, 255, 255, 0))
draw = ImageDraw.Draw(overlay_image)

# Draw the route as a red line
for i in range(len(coordinates) - 1):
    lon1, lat1 = coordinates[i]
    lon2, lat2 = coordinates[i + 1]
    x1, y1 = lat_lon_to_pixel(lat1, lon1, xllcorner, yllcorner, cellsize, nrows)
    x2, y2 = lat_lon_to_pixel(lat2, lon2, xllcorner, yllcorner, cellsize, nrows)
    draw.line((x1, y1, x2, y2), fill=(255, 0, 0, 128), width=3)

# Draw waypoints as blue circles
for waypoint in waypoints:
    # waypoint["location"] is [lon, lat]
    wlon, wlat = waypoint["location"]
    x, y = lat_lon_to_pixel(wlat, wlon, xllcorner, yllcorner, cellsize, nrows)

    draw.ellipse([x - 5, y - 5, x + 5, y + 5], fill=(0, 0, 255, 128))

    # Add text near the waypoint (just showing coordinates here)
    waypoint_info = f"({wlon:.5f}, {wlat:.5f})"
    draw.text((x + 10, y - 10), waypoint_info, fill=(255, 255, 255, 255))

# Combine the original image and the overlay
combined_image = Image.alpha_composite(base_image, overlay_image)

# Save the result
combined_image.save("output_overlay_with_waypoints.png")

# Display the result
plt.imshow(combined_image)
plt.axis("off")
plt.show()
