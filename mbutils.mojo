from math import floor, log10
from sys import argv, has_accelerator

from structures import ScreenSize

def check_gpu():
    @parameter
    if not has_accelerator():
        raise Error("No compatible GPU found")

def parse_args() -> ScreenSize:
    args = argv()
    if len(args) == 1:
        return ScreenSize(1280, 720)
    elif len(args) == 2:
        if args[1] in {"4K", "4k"}:
            return ScreenSize(3840, 2160)
        height = Int(args[1])
        if height in {720, 1080}:
            base = height // 9
            return ScreenSize(base * 16, height)
        else:
            base = height // 3
            return ScreenSize(base * 4, height)
    elif len(args) == 3:
        return ScreenSize(Int(args[1]), Int(args[2]))
    else:
        raise Error('Cannot parse args')

def format_sig_fig[F: DType](num: Scalar[F], sf: UInt) -> String:
    if num < 0:
        sign = "-"
    else:
        sign = ""
    x = abs(num)
    n_digits = floor(log10(x)) + 1
    factor = 10 ** (n_digits - 1)
    rounded = round(x / factor, sf - 1)
    if n_digits < sf:
        string_slice = String(rounded * factor)
        if x < 1:
            # n_digits actually refers to the number of 0s after the .
            return "{}{}e{}".format(sign, String(rounded), Int(n_digits) - 1)
        else:
            sliced = string_slice[slice(0, sf + 1)]
            return sign + String(sliced)
    power = 10 ** sf
    x_digit = Int(rounded * power)
    remaining_factor = Int(factor / power)
    if remaining_factor == 0:
        return "{}{}".format(sign, x_digit)
    return "{}{}".format(sign, x_digit * remaining_factor)

# def main():
#     print(format_sig_fig(.012345, 3))
#     print(format_sig_fig(.12345, 3))
#     print(format_sig_fig(1.2345, 3))
#     print(format_sig_fig(12.345, 3))
#     print(format_sig_fig(123.45, 3))
#     print(format_sig_fig(1234.5, 3))
#     print(format_sig_fig(12345, 3))
