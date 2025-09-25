from gpu import global_idx
from gpu.host import DeviceContext
from python import Python
from subprocess import subprocess

from structures import ftype, itype, Image, ImageCoords, ScreenSize
from mbutils import check_gpu, parse_args

alias TPB = 8
alias THREADS_PER_BLOCK = (TPB, TPB)


alias MAX_ITERS = 255

fn mandelbrot_unsafe(
    output: UnsafePointer[Scalar[itype]],
    width: UInt,
    height: UInt,
    xmin: Scalar[ftype],
    ymin: Scalar[ftype],
    xscale: Scalar[ftype],
    yscale: Scalar[ftype],
):
    row = global_idx.y
    col = global_idx.x
    x = xmin + Scalar[ftype](col) * xscale
    y = ymin + Scalar[ftype](row) * yscale
    if row < height and col < width:
        iters = mandelbrot_core(row, col, x, y)
    else:
        iters = 0
    idx = row * width + col
    output[idx] = iters


fn mandelbrot_core(
    row: UInt,
    col: UInt,
    x: Scalar[ftype],
    y: Scalar[ftype],
) -> Scalar[itype]:
    var iters: Scalar[itype] = 0
    zx: Scalar[ftype] = 0.0
    zy: Scalar[ftype] = 0.0
    zx2: Scalar[ftype] = 0.0
    zy2: Scalar[ftype] = 0.0
    # TODO: rewrite this to be both less footgunny and faster
    #       figure out how to use simd etc
    z2 = x * x + y * y
    while iters < MAX_ITERS and z2 < 4.0:
        # Note zy computation needs to come before zx
        # because we use zx in zy, but don't use zy in zx
        zy = 2 * zx * zy + y
        zx = zx2 - zy2 + x
        zx2 = zx**2
        zy2 = zy**2
        z2 = zx2 + zy2
        iters += 1
    return iters

def generate_image(ctx: DeviceContext, image_coords: ImageCoords, screen_size: ScreenSize) -> Image:
    out = ctx.enqueue_create_buffer[itype](Int(screen_size.get_pixels())).enqueue_fill(0)
    ctx.enqueue_function[mandelbrot_unsafe](
        out.unsafe_ptr(),
        screen_size.width,
        screen_size.height,
        image_coords.xmin,
        image_coords.ymin,
        image_coords.get_xscale(screen_size),
        image_coords.get_yscale(screen_size),
        grid_dim=screen_size.get_blocks_per_grid(THREADS_PER_BLOCK),
        block_dim=THREADS_PER_BLOCK,
    )

    ctx.synchronize()

    with out.map_to_host() as out_host:
        image = Image(out_host.unsafe_ptr(), screen_size, MAX_ITERS)
    return image^

def main():
    check_gpu()
    screen_size = parse_args()
    with DeviceContext() as ctx:
        print("Found GPU:", ctx.name())

        coords = screen_size.get_default_image_coords()

        blocks_per_grid = screen_size.get_blocks_per_grid(THREADS_PER_BLOCK)
        print(
            "Running kernel with grid_dim=(",
            blocks_per_grid[0], ", ", blocks_per_grid[1], "), "
            "block_dim=(",
            THREADS_PER_BLOCK[0], ", ", THREADS_PER_BLOCK[1], ")"
        )

        image = generate_image(ctx, coords, screen_size)
        print(hash(image))

        filename = "mandelbrot"
        image.write_pgm(filename)
        # Convert to png
        _ = subprocess.run("magick convert " + filename + ".pgm " + filename + ".png")
        _ = subprocess.run("rm " + filename + ".pgm")
