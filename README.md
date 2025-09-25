# Mojo Mandelbrot Set Renderer

A toy project to showcase a zoomable Mandelbrot set renderer written in Mojo
with an interactive pygame-based viewer. The aim is to explore Mojo, and writing code for GPUs.
Initial thoughts are that this is a lot easier to write than CUDA.

Nothing is cached; all images are computed on the fly.

It was intended that a user should be able to infinitely explore the mandelbrot set, but due
to floating point precision limits, things get a bit fuzzy at 100,000x zoom.

Options for improving this (that will not be implemented by the author) include:
* Using double precision floats
  * this needs to be run on a CPU, which does not fulfill the goal of learning GPU programming
* [Calculating key points in high precision and perturbing them](https://mathr.co.uk/blog/2021-05-14_deep_zoom_theory_and_practice.html)

`LayoutTensors` are **not** used here, as computations return incorrect data when the size
of the tensor is greater than ~3000 bytes, as of `Mojo 0.25.7.0.dev2025092205 (22942900)`.
See https://github.com/modular/modular/issues/5362

## Requirements and Installation

If on Mac OS Arm64 (only platform this is tested on):
- Mac OS 15+
- Xcode 16+

```bash
# Clone and cd into the repo, then
# Install pixi if required
curl -fsSL https://pixi.sh/install.sh | sh
pixi self-update
# Optional: install imagemagick (for static png generation)
brew install imagemagick
pixi shell
# Run the viewer
mojo display.mojo
```

## Interactive Viewer Usage

Run the interactive viewer with pygame GUI:

```bash
mojo display.mojo [resolution]
```

**Resolution options:**
- No arguments: 1280x720 (default)
- Single argument:
  - `4K` or `4k`: 3840x2160
  - `720` or `1080`: 16:9 aspect ratio (1280x720 or 1920x1080)
  - Other heights: 4:3 aspect ratio
- Two arguments: custom width and height

**Controls:**
- **Mouse wheel**: Zoom in/out at cursor position
- **Left click + drag**: Pan the view
- **R key**: Reset to default view
- **Q key**: Quit

### Static Image Generation

Generate a static PNG image:

```bash
mojo mandelbrot.mojo [resolution]
```

This `mandelbrot.png` files in the current directory.

## Code Structure

- **`mandelbrot.mojo`**: Core Mandelbrot computation and static image generation
- **`display.mojo`**: Interactive pygame viewer with zoom/pan functionality
- **`structures.mojo`**: Data structures for coordinates, screen size, and images
- **`mbutils.mojo`**: Utility functions for argument parsing and formatting
