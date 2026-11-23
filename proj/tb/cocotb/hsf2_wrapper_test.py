"""Parameterized HSF2 regression for a single elaborated DUT.

The launcher selects E, M, and the rounding mode. HSF2_EXPONENT_WIDTH,
HSF2_MANTISSA_WIDTH, and HSF2_ROUND_MODE can supply parameters hidden by VPI.
HSF2_SEED, HSF2_RANDOM_CASES, and HSF2_EXHAUSTIVE_BITS control run size.
"""

import logging
import os
import random
from dataclasses import dataclass
from itertools import chain, product

import cocotb
import pytest
from cocotb.clock import Clock

from FloatingPoint import FloatingPoint, FloatingPointRoundingMode as Rounding
from FpMultiplierTestbench import FpMultiplierTestbench, PIPELINE_LATENCY
from FpMultiplierTransactions import FpMultiplierOperandInputTransaction as InputTransaction


LOG = logging.getLogger(f"cocotb.{__name__}")
TIMEOUT = {"timeout_time": 50, "timeout_unit": "ms"}


def _mode_number(value):
    try:
        return int(value)
    except (TypeError, ValueError):
        name = str(value).split("::")[-1].removeprefix("FP_ROUND_MODE_")
        if name == "TIES_TO_EVEN":
            return Rounding.NEAREST_EVEN.value
        try:
            return Rounding[name].value
        except KeyError as error:
            raise ValueError(f"Unknown rounding mode {value!r}") from error


def _parameter(dut, name, env, parse=int):
    configured = os.getenv(env)
    setting = parse(configured) if configured is not None else None
    try:
        actual = parse(getattr(dut, name).value)
    except (AttributeError, TypeError, ValueError) as error:
        if setting is not None:
            return setting
        raise AssertionError(f"Cannot read {name} from DUT. Set {env} to its elaborated value.") from error
    assert setting is None or actual == setting, f"{name}={actual} disagrees with {env}={setting}"
    return actual


@dataclass(frozen=True)
class Format:
    e: int
    m: int
    mode: Rounding

    @property
    def width(self):
        return 1 + self.e + self.m

    @property
    def exp_max(self):
        return (1 << self.e) - 1

    @property
    def hidden(self):
        return 1 << self.m

    @property
    def sign_bit(self):
        return 1 << (self.e + self.m)

    @property
    def inf(self):
        return self.exp_max << self.m

    def power(self, biased_exp):
        if 1 <= biased_exp < self.exp_max:
            return biased_exp << self.m
        if 1 - self.m <= biased_exp <= 0:
            return self.hidden >> (1 - biased_exp)
        return 0


def _read_format(dut):
    fmt = Format(
        _parameter(dut, "EXPONENT_WIDTH", "HSF2_EXPONENT_WIDTH"),
        _parameter(dut, "MANTISSA_WIDTH", "HSF2_MANTISSA_WIDTH"),
        Rounding(_parameter(dut, "FP_ROUND_MODE", "HSF2_ROUND_MODE", _mode_number)),
    )
    assert 1 <= fmt.e <= 32 and 1 <= fmt.m <= 128, f"Unsupported RTL format {fmt}"
    for port in (dut.op_a_in, dut.op_b_in, dut.result_out):
        assert len(port) == fmt.width, f"Port width {len(port)} disagrees with {fmt}"
    return fmt


def _integer_oracle(fmt, a, b):
    """Exact integer multiplication for formats wider than 64 bits."""
    mag_mask = fmt.sign_bit - 1
    x, y = a & mag_mask, b & mag_mask
    sign = (a ^ b) & fmt.sign_bit
    toward_negative = fmt.mode == Rounding.TOWARD_NEGATIVE

    if x > fmt.inf or y > fmt.inf or (x == fmt.inf and y == 0) or (y == fmt.inf and x == 0):
        return fmt.inf | 1
    if x == fmt.inf or y == fmt.inf:
        return sign | fmt.inf
    if x == 0 or y == 0:
        return sign

    exp_x, mantissa_x = divmod(x, fmt.hidden)
    exp_y, mantissa_y = divmod(y, fmt.hidden)
    if exp_x:
        mantissa_x |= fmt.hidden
    if exp_y:
        mantissa_y |= fmt.hidden
    exp_x, exp_y = max(1, exp_x), max(1, exp_y)
    exact = mantissa_x * mantissa_y
    product_exp = exp_x + exp_y - fmt.exp_max // 2
    exponent = max(1, product_exp + exact.bit_length() - 1 - 2 * fmt.m)
    shift = exponent - product_exp + fmt.m
    outward = (
        (fmt.mode == Rounding.TOWARD_POSITIVE and not sign)
        or (toward_negative and bool(sign))
    )
    if shift > exact.bit_length():
        # The nonzero product is below half the smallest subnormal.
        return sign | int(outward)

    scale = 1 << max(0, shift)
    mantissa, remainder = divmod(exact << max(0, -shift), scale)
    if fmt.mode == Rounding.NEAREST_EVEN:
        twice = remainder * 2
        increment = twice > scale or (twice == scale and bool(mantissa & 1))
    else:
        increment = outward and remainder != 0
    mantissa += int(increment)
    if mantissa >= 2 * fmt.hidden:
        mantissa >>= 1
        exponent += 1
    if mantissa < fmt.hidden:
        exponent = 0
    if exponent >= fmt.exp_max:
        return sign | (fmt.inf if fmt.mode == Rounding.NEAREST_EVEN or outward else fmt.inf - 1)
    return sign | (exponent << fmt.m) | (mantissa & (fmt.hidden - 1))


def _expected(fmt, a, b):
    if fmt.width > 64:
        return _integer_oracle(fmt, a, b)
    x = FloatingPoint(fmt.m, fmt.e, a)
    y = FloatingPoint(fmt.m, fmt.e, b)
    return FloatingPoint.mul(x, y, fmt.mode).get_binary()


def _make_testbench(dut, fmt=None):
    if fmt is None:
        fmt = _read_format(dut)
    seed = int(os.getenv("HSF2_SEED", "42"), 0)
    context = f"E={fmt.e} M={fmt.m} mode={fmt.mode.name} seed={seed}"
    bench = FpMultiplierTestbench(
        dut, en_backpressure=False, exponent_width=fmt.e, mantissa_width=fmt.m,
        predictor=lambda a, b: _expected(fmt, a, b), seed=seed, context=context,
    )
    Clock(dut.clk, 10, unit="ns").start(start_high=False)
    oracle = "FloatingPoint" if fmt.width <= 64 else "exact integer"
    LOG.info("%s oracle=%s", context, oracle)
    return bench, fmt, seed


def _directed_vectors(fmt):
    largest = fmt.inf - 1
    magnitudes = {0, 1, fmt.hidden - 1, largest, fmt.inf, fmt.inf | 1, fmt.inf | (fmt.hidden - 1)}
    if fmt.exp_max > 1:
        magnitudes.update((fmt.hidden, fmt.hidden + 1, largest - 1))
        one = fmt.power(fmt.exp_max // 2)
        magnitudes.update((one - 1, one, one + 1))
    signed = sorted(magnitudes | {value | fmt.sign_bit for value in magnitudes})
    for a, b in product(signed, repeat=2):
        yield InputTransaction(a, b)

    if fmt.exp_max == 1:
        return
    bias = fmt.exp_max // 2
    half, one, two = (fmt.power(bias + offset) for offset in (-1, 0, 1))
    edge = (fmt.exp_max - 1) << fmt.m
    half_mantissa = fmt.hidden >> 1
    pairs = {
        (largest, two),
        (edge | half_mantissa, one | half_mantissa),
        (edge | 1, two - 2),
        (fmt.hidden, one - 1),
        (fmt.hidden, half),
        (1, half - 1), (1, half), (1, half + 1),
        (one | 1, one | half_mantissa),
    }
    for (a, b), sign_a, sign_b in product(sorted(pairs), (0, fmt.sign_bit), (0, fmt.sign_bit)):
        yield InputTransaction(a | sign_a, b | sign_b)
        yield InputTransaction(b | sign_b, a | sign_a)


def _random_finite_vectors(fmt, rng, count):
    max_exp = fmt.exp_max - 1
    bias = fmt.exp_max // 2
    edges = sorted({0, min(1, max_exp), bias, max(0, max_exp - 1), max_exp})
    product_exponents = (-fmt.m - 1, -fmt.m, 0, 1, max_exp, max_exp + 1)
    for index in range(count):
        exp_a = rng.randint(0, max_exp)
        exp_b = rng.randint(0, max_exp)
        sign_a = rng.choice((0, fmt.sign_bit))
        sign_b = rng.choice((0, fmt.sign_bit))
        if index % 4 == 1:
            exp_a, exp_b = rng.choice(edges), rng.choice(edges)
        elif index % 4 == 2:
            exp_b = max(0, min(max_exp, bias + rng.choice(product_exponents) - max(1, exp_a)))
        elif index % 4 == 3:
            exp_b = max(0, min(max_exp, 2 * bias - max(1, exp_a)))
        a = (exp_a << fmt.m) | rng.getrandbits(fmt.m)
        b = (exp_b << fmt.m) | rng.getrandbits(fmt.m)
        yield InputTransaction(a | sign_a, b | sign_b)


def _random_count():
    count = int(os.getenv("HSF2_RANDOM_CASES", "20000"), 0)
    assert count > 0, "HSF2_RANDOM_CASES must be positive"
    return count


@cocotb.test(**TIMEOUT)
async def directed_extremes(dut):
    bench, fmt, _ = _make_testbench(dut)
    await bench.reset()
    await bench.run(_directed_vectors(fmt))


@cocotb.test(**TIMEOUT)
async def random_binary(dut):
    bench, fmt, seed = _make_testbench(dut)
    rng = random.Random(seed ^ 0x42494E)
    vectors = (InputTransaction(rng.getrandbits(fmt.width), rng.getrandbits(fmt.width))
               for _ in range(_random_count()))
    await bench.reset()
    await bench.run(vectors)


@cocotb.test(**TIMEOUT)
async def random_finite(dut):
    bench, fmt, seed = _make_testbench(dut)
    rng = random.Random(seed ^ 0x46494E)
    await bench.reset()
    await bench.run(_random_finite_vectors(fmt, rng, _random_count()),
                    source_probability=0.85, ready_probability=0.70)


@cocotb.test(**TIMEOUT)
async def exhaustive_small(dut):
    fmt = _read_format(dut)
    limit = int(os.getenv("HSF2_EXHAUSTIVE_BITS", "8"), 0)
    assert 0 <= limit <= 10, "HSF2_EXHAUSTIVE_BITS must be between 0 and 10"
    if fmt.width > limit:
        pytest.skip(f"{fmt.width} bits exceeds the {limit}-bit exhaustive limit")
    bench, _, _ = _make_testbench(dut, fmt)
    await bench.reset()
    await bench.run(InputTransaction(a, b) for a, b in product(range(1 << fmt.width), repeat=2))


@cocotb.test(**TIMEOUT)
async def flow_control(dut):
    bench, fmt, seed = _make_testbench(dut)
    stall_vectors = [
        InputTransaction(fmt.inf, 0), InputTransaction(fmt.inf, fmt.inf | fmt.sign_bit),
        InputTransaction(1, 1), InputTransaction(1, 0),
    ]

    await bench.reset()
    await bench.run(_random_finite_vectors(fmt, random.Random(seed), 32))
    assert bench.scoreboard.checked == 32 and bench.stalled_input == 0, bench.context
    assert bench.first_output - bench.first_input == PIPELINE_LATENCY, bench.context
    assert bench.last_output - bench.first_output + 1 == bench.scoreboard.checked, bench.context

    await bench.reset()
    vectors = iter(stall_vectors)
    pending = next(vectors)
    for _ in range(12):
        if await bench.step(pending, ready=False):
            pending = next(vectors, None)
    assert bench.accepted == PIPELINE_LATENCY and bench.stalled_input and bench.stalled_output, bench.context
    await bench.run(chain(vectors, (InputTransaction(0, 0),)), held_input=pending)
    assert bench.scoreboard.checked == len(stall_vectors) + 1, bench.context

    await bench.reset()
    for vector in stall_vectors[:PIPELINE_LATENCY]:
        assert await bench.step(vector, ready=False), bench.context
    assert bench.scoreboard.pending == PIPELINE_LATENCY and bench.scoreboard.checked == 0, bench.context
    await bench.reset()
    await bench.run([
        InputTransaction(0, 0), InputTransaction(1 | fmt.sign_bit, 0),
        InputTransaction(fmt.inf | 1, 1),
    ])
    assert bench.scoreboard.checked == 3, bench.context
