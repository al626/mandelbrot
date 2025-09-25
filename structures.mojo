from hashlib.hasher import Hasher
from math import ceildiv

alias ftype = DType.float32
alias itype = DType.int32
alias utype = DType.uint32

@fieldwise_init
struct ImageCoords(Copyable, Movable, ImplicitlyCopyable, Stringable):
    var xmin: Scalar[ftype]
    var xmax: Scalar[ftype]
    var ymin: Scalar[ftype]
    var ymax: Scalar[ftype]

    fn __str__(self) -> String:
        return (
            "ImageCoords(" +
            "xmin=" + String(self.xmin) + ", " +
            "xmax=" + String(self.xmax) + ", " +
            "ymin=" + String(self.ymin) + ", " +
            "ymax=" + String(self.ymax) +
            ")"
        )

    def get_xscale(self, screen_size: ScreenSize) -> Scalar[ftype]:
        return (self.xmax - self.xmin) / Scalar[ftype](screen_size.width)

    def get_yscale(self, screen_size: ScreenSize) -> Scalar[ftype]:
        return (self.ymax - self.ymin) / Scalar[ftype](screen_size.height)

    def get_scale(self, screen_size: ScreenSize) -> (Scalar[ftype], Scalar[ftype]):
        return self.get_xscale(screen_size), self.get_yscale(screen_size)

@fieldwise_init
struct ScreenSize(Copyable, Movable, ImplicitlyCopyable, Stringable, Hashable):
    var width: Scalar[utype]
    var height: Scalar[utype]

    fn __str__(self) -> String:
        return (
            "ScreenSize(" +
            "width=" + String(self.width) + ", " +
            "height=" + String(self.height) +
            ")"
        )

    fn __hash__[H: Hasher](self, mut hasher: H):
        hasher.update(self.width)
        hasher.update(self.height)

    fn get_pixels(self) -> Scalar[utype]:
        return self.width * self.height

    def get_resolution(self) -> Scalar[ftype]:
        return Scalar[ftype](self.width) / Scalar[ftype](self.height)

    def is_16_9(self) -> Bool:
        return abs(self.get_resolution() - 16.0 / 9.0) < 1e-6

    def is_4_3(self) -> Bool:
        return abs(self.get_resolution() - 4.0 / 3.0) < 1e-6

    def get_blocks_per_grid(
        self, threads_per_block: (Int, Int)
    ) -> (Scalar[utype], Scalar[utype]):
        return (
            ceildiv(self.width, threads_per_block[0]),
            ceildiv(self.height, threads_per_block[1]),
        )

    def get_default_image_coords(self) -> ImageCoords:
        if self.is_4_3():
            return ImageCoords(-2.5, 1.5, -1.5, 1.5)
        if self.is_16_9():
            return ImageCoords(-2.5, 1.5, -1.125, 1.125)
        resolution = self.get_resolution()
        if resolution > Scalar[ftype](16.0 / 9.0):
            return ImageCoords(-2.5 * resolution, 1.5 * resolution, -1.125, 1.125)
        else:
            return ImageCoords(-2.5, 1.5, -2 / resolution, 2 / resolution)


@fieldwise_init
struct Image(Movable, Hashable):
    var image: UnsafePointer[Scalar[itype]]
    var screen_size: ScreenSize
    var max_value: UInt

    fn __hash__[H: Hasher](self, mut hasher: H):
        hasher.update(hash(self.screen_size))
        hasher.update(self.max_value)
        for idx in range(self.screen_size.get_pixels()):
            hasher.update(self.image[idx])

    def get_value(self, row: Scalar[utype], col: Scalar[utype]) -> Scalar[itype]:
        return self.image[row * self.screen_size.width + col]

    def write_pgm(self, filename: String):
        full_filename = filename + ".pgm"
        print("Writing image to", full_filename)
        with open(full_filename, 'w') as f:
            # First the header
            f.write("P2\n")
            f.write(String(self.screen_size.width), " ", String(self.screen_size.height), "\n")
            f.write(String(self.max_value), "\n")
            # Now the contents
            for row in range(self.screen_size.height):
                line_str = String()
                for col in range(self.screen_size.width):
                    line_str += String(self.get_value(row, col)) + " "
                f.write(line_str, "\n")
