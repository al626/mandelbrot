from gpu.host import DeviceContext
from logger import Logger
from math import log10, floor
from python import Python, PythonObject
from sys import argv
import time

from mandelbrot import generate_image
from mbutils import parse_args, check_gpu, format_sig_fig
from structures import ScreenSize, ImageCoords, ftype, Image

alias USE_COLOR = False
alias USE_EXPONENTIAL_MAP = False

struct ImageViewer:
    var screen_size: ScreenSize
    var orig_image_coords: ImageCoords
    var zoom: Scalar[ftype]
    var max_zoom: Scalar[ftype]
    var zoom_step: Scalar[ftype]
    var offset_x: Scalar[ftype]
    var offset_y: Scalar[ftype]
    var dragging: Bool
    var last_mouse_x: Int
    var last_mouse_y: Int
    var image_width: Int
    var image_height: Int
    var needs_update: Bool
    var _time_since_log: Float64
    var logger: Logger

    def __init__(out self, screen_size: ScreenSize):
        self.screen_size = screen_size
        self.orig_image_coords = screen_size.get_default_image_coords()
        self.zoom = 1.0
        self.max_zoom = Scalar[ftype].MAX_FINITE
        self.zoom_step = 1.2
        # Offset is in image coords
        self.offset_x = 0.0
        self.offset_y = 0.0
        # Internal state
        self.dragging = False
        self.last_mouse_x = 0
        self.last_mouse_y = 0
        self.image_width = 0
        self.image_height = 0
        self.needs_update = False
        self._time_since_log = 0
        self.logger = Logger()

    def reset(mut self):
        self.zoom = 1.0
        self.offset_x = 0.0
        self.offset_y = 0.0

    def get_image_coords(self) -> ImageCoords:
        oic = self.orig_image_coords
        return ImageCoords(
            oic.xmin + self.offset_x,
            oic.ymin + self.offset_y,
            oic.w / self.zoom,
            oic.h / self.zoom,
        )

    def gen_image(self, ctx: DeviceContext) -> Image:
        """Load the mandelbrot set image based on current coordinates."""
        coords = self.get_image_coords()
        return generate_image(ctx, coords, self.screen_size)

    def screen_to_world(self, screen_x: Int, screen_y: Int) -> (Float64, Float64):
        """Convert screen coordinates to world (image) coordinates."""
        # world_x = (Float64(screen_x) - Float64(self.screen_width) / 2.0) / self.zoom + self.offset_x
        # world_y = (Float64(screen_y) - Float64(self.screen_height) / 2.0) / self.zoom + self.offset_y
        # return (world_x, world_y)
        return (1.0, 1.0)

    def world_to_screen(self, world_x: Float64, world_y: Float64) -> (Float64, Float64):
        """Convert world coordinates to screen coordinates."""
        # screen_x = (world_x - self.offset_x) * self.zoom + Float64(self.screen_width) / 2.0
        # screen_y = (world_y - self.offset_y) * self.zoom + Float64(self.screen_height) / 2.0
        # return (screen_x, screen_y)
        return (0, 0)

    def get_xscale(self) -> Scalar[ftype]:
        return self.orig_image_coords.get_xscale(self.screen_size) / self.zoom

    def get_yscale(self) -> Scalar[ftype]:
        return self.orig_image_coords.get_yscale(self.screen_size) / self.zoom

    def set_offset(mut self, o_x: Scalar[ftype], o_y: Scalar[ftype]) -> Bool:
        """
        Sets offset_x/offset_y, clipping to ensure we don't exceed image bounds.
        Returns true if updated.
        """
        updated = False
        w = self.orig_image_coords.w
        h = self.orig_image_coords.h
        ox_max = w * (1 - 1 / self.zoom)
        oy_max = h * (1 - 1 / self.zoom)

        if o_x < 0:
            updated |= self.offset_x != 0
            self.offset_x = 0
        elif o_x > ox_max:
            updated |= self.offset_x != ox_max
            self.offset_x = ox_max
        else:
            updated |= self.offset_x != o_x
            self.offset_x = o_x

        if o_y < 0:
            updated |= self.offset_y != 0
            self.offset_y = 0
        elif o_y > oy_max:
            updated |= self.offset_y != oy_max
            self.offset_y = oy_max
        else:
            updated |= self.offset_y != o_y
            self.offset_y = o_y

        return updated

    def zoom_at_point(mut self, screen_x: Int, screen_y: Int, zoom_factor: Scalar[ftype]) -> Bool:
        """
        Zoom in/out while keeping the point under the cursor stationary.
        Returns true if updated.
        """

        # Load up some variables to keep things neat
        w = self.orig_image_coords.w
        h = self.orig_image_coords.h
        z0 = self.zoom
        z1 = max(1, min(self.max_zoom, z0 * zoom_factor))
        if z0 == z1:
            # Zoom unchanged, so nothing to do
            return False

        # Fraction of the screen the cursor is away from
        x_f = Scalar[ftype](screen_x) / Scalar[ftype](self.screen_size.width)
        y_f = Scalar[ftype](screen_y) / Scalar[ftype](self.screen_size.height)

        # Determine the offset required to keep the fraction the same at the relevant zoom
        o_x = self.offset_x + x_f * ( w / z0 - w / z1 )
        o_y = self.offset_y + y_f * ( h / z0 - h / z1 )

        # Assign values
        self.zoom = z1
        _ = self.set_offset(o_x, o_y)

        return True

    def draw(self, pygame: PythonObject, screen: PythonObject, image: Image) -> None:
        """Draw the current view."""
        # Gray background
        # screen.fill(Python.tuple(50, 50, 50))

        # Calculate where to draw the image on screen
        for row in range(image.screen_size.height):
            for col in range(image.screen_size.width):
                @parameter
                if USE_EXPONENTIAL_MAP:
                    magic_power = 2
                    norm = Scalar[ftype](image.get_value(row, col)) / image.max_value
                    color = Int(((norm ** magic_power * 255) ** 1.5)) % 255
                else:
                    color = Int(image.get_value(row, col)) * 255 // image.max_value
                @parameter
                if USE_COLOR:
                    base = color * 3
                    color_tuple = pygame.Color(
                        max(0, min(255, base - 255 * 2)),
                        max(0, min(255, base - 255)),
                        max(0, min(255, base)),
                    )
                else:
                    color_tuple = pygame.Color(color, color, color)
                screen.set_at(Python.tuple(col, row), color_tuple)

        # Draw info
        var font = pygame.font.Font(None, 36)
        var zoom_text = "Zoom: {}x".format(format_sig_fig(self.zoom, 3))
        c = self.get_image_coords()
        # var coords_text = "Coords: ({}, {}) -> ({}, {})".format(
        #     format_sig_fig(c.xmin, 3),
        #     format_sig_fig(c.ymin, 3),
        #     format_sig_fig(c.xmax, 3),
        #     format_sig_fig(c.ymax, 3),
        # )
        # var info_text = "{}\n{}".format(zoom_text, coords_text)
        var text_surface = font.render(zoom_text, True, Python.tuple(255, 255, 255))
        screen.blit(text_surface, Python.tuple(10, 10))

        pygame.display.flip()

    def handle_events(mut self, pygame: PythonObject) -> Bool:
        """Handle pygame events."""
        for event in pygame.event.get():
            if Int(event.type) == Int(pygame.QUIT):
                self.logger.debug("QUIT")
                return False

            elif Int(event.type) == Int(pygame.MOUSEWHEEL):
                # Zoom at mouse cursor
                var mouse_pos = pygame.mouse.get_pos()
                var mouse_x = Int(mouse_pos[0])
                var mouse_y = Int(mouse_pos[1])
                var event_y = Int(event.y)
                self.logger.debug(
                    "MOUSEWHEEL at ({}, {}), event.y={}".format(mouse_x, mouse_y, event_y)
                )

                if event_y != 0:
                    if event_y > 0:  # Scroll up - zoom in
                        zoom = event_y * self.zoom_step
                    else:  # Scroll down - zoom out
                        zoom = 1 / (self.zoom_step * abs(event_y))
                    self.needs_update = self.zoom_at_point(mouse_x, mouse_y, zoom)

            elif Int(event.type) == Int(pygame.MOUSEBUTTONDOWN):
                var event_button = Int(event.button)
                if event_button == 1:  # Left mouse button
                    self.dragging = True
                    var mouse_pos = pygame.mouse.get_pos()
                    self.logger.debug("LEFTMOUSEBUTTONDOWN, pos: {}".format(String(mouse_pos)))
                    self.last_mouse_x = Int(mouse_pos[0])
                    self.last_mouse_y = Int(mouse_pos[1])

            elif Int(event.type) == Int(pygame.MOUSEBUTTONUP):
                var event_button = Int(event.button)
                if event_button == 1:  # Left mouse button
                    var mouse_pos = pygame.mouse.get_pos()
                    self.logger.debug("LEFTMOUSEBUTTONUP, pos: {}".format(String(mouse_pos)))
                    self.dragging = False
                    self.needs_update = True

            elif Int(event.type) == Int(pygame.MOUSEMOTION):
                if self.dragging:
                    var mouse_pos = pygame.mouse.get_pos()
                    var mouse_x = Int(mouse_pos[0])
                    var mouse_y = Int(mouse_pos[1])
                    var dx = (mouse_x - self.last_mouse_x) * self.get_xscale()
                    var dy = (mouse_y - self.last_mouse_y) * self.get_yscale()

                    # Pan the view
                    self.logger.debug("Panning by ({}, {})".format(dx, dy))
                    self.needs_update = self.set_offset(self.offset_x - dx, self.offset_y - dy)
                    self.last_mouse_x = mouse_x
                    self.last_mouse_y = mouse_y

            elif Int(event.type) == Int(pygame.KEYDOWN):
                event_key = Int(event.key)
                self.logger.debug("KEYDOWN: {}".format(event_key))
                if event_key == Int(pygame.K_r):
                    # Reset view
                    self.zoom = 1.0
                    self.offset_x = Scalar[ftype](self.image_width) / 2.0
                    self.offset_y = Scalar[ftype](self.image_height) / 2.0
                    self.needs_update = True
                if event_key == Int(pygame.K_q):
                    # Quit
                    return False

        return True

    def run(mut self) -> None:
        """Main loop."""
        check_gpu()
        # Import pygame
        var pygame = Python.import_module("pygame")
        pygame.init()

        var screen = pygame.display.set_mode(Python.tuple(
            self.screen_size.width, self.screen_size.height,
        ))
        pygame.display.set_caption("Mandelbrot")

        with DeviceContext() as ctx:
            print("Found GPU:", ctx.name())

            # Create example image
            var image = self.gen_image(ctx)
            self.logger.debug("Generated image")
            self.draw(pygame, screen, image)
            self.logger.debug("Drew image")

            # Main loop
            var clock = pygame.time.Clock()
            var running = True

            while running:
                running = self.handle_events(pygame)

                if self.needs_update:
                    image = self.gen_image(ctx)
                    self.draw(pygame, screen, image)
                    self.needs_update = False
                    self.logger.debug("Image redrawn with coords {}".format(
                        String(self.get_image_coords()),
                    ))
                clock.tick(60)

        pygame.quit()


def main():
    screen_size = parse_args()
    print("Running with ", String(screen_size))
    var viewer = ImageViewer(screen_size)
    viewer.run()
