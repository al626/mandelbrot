from complex import ComplexSIMD
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
    # x = xmin + col * xscale
    x = xscale.fma(Scalar[ftype](col), xmin)
    # y = ymin + row * yscale
    y = yscale.fma(Scalar[ftype](row), ymin)
    if row < height and col < width:
        iters = mandelbrot_core(row, col, x, y)
    else:
        iters = 0
    idx = row * width + col
    output[idx] = iters


fn mandelbrot_core(
    row: UInt,
    col: UInt,
    cx: Scalar[ftype],
    cy: Scalar[ftype],
) -> Scalar[itype]:
    var iters: Scalar[itype] = 0
    var z = ComplexSIMD[ftype, 1](0, 0)
    var c = ComplexSIMD[ftype, 1](cx, cy)
    for _ in range(MAX_ITERS):
        mask_ok = z.squared_norm().le(4)
        iters = mask_ok.select(iters + 1, iters)
        z = z.squared_add(c)
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
        # Example that shows limits of f32 precision
        # coords = ImageCoords(xmin=-0.71209693, ymin=-0.30181742, w=7.849487e-06, h=5.887115e-06)

        image = generate_image(ctx, coords, screen_size)
        print(hash(image))

        filename = "mandelbrot"
        image.write_pgm(filename)
        # Convert to png
        _ = subprocess.run("magick convert " + filename + ".pgm " + filename + ".png")
        _ = subprocess.run("rm " + filename + ".pgm")
