import random
import numpy as np
import logging

import cocotb
import pytest
from cocotb.clock import Clock

from FpMultiplierTestbench import FpMultiplierTestbench
from FpMultiplierTransactions import FpMultiplierOperandInputTransaction
import FloatingPoint

def genResultVectors(duv, opVectors : list):
    resultTestVectors = []
    for opVec in opVectors:
        # Use the reference model to compute expected result
        mantissaBits = int(duv.MANTISSA_WIDTH.value)
        exponentBits = int(duv.EXPONENT_WIDTH.value)

        fpA = FloatingPoint.FloatingPoint(mantissaBits, exponentBits)
        fpB = FloatingPoint.FloatingPoint(mantissaBits, exponentBits)

        fpA.setBinary(opVec.operandA)
        fpB.setBinary(opVec.operandB)

        fpResult = fpA * fpB
        resultTestVectors.append((fpA, fpB, fpResult))
    return resultTestVectors

@cocotb.test()
async def verySimpleTest(duv):
    tb = FpMultiplierTestbench(duv, False)

    # Prepare simple test vectors
    opVector = [1.0, 1.5, -1.5, 2.5]
    opTestVectors = []
    for a in opVector:
        for b in opVector:
            fpA = FloatingPoint.FloatingPoint.fromFloat32(a)
            fpB = FloatingPoint.FloatingPoint.fromFloat32(b)
            opInVec = FpMultiplierOperandInputTransaction(fpA.getBinary(), fpB.getBinary())
            opTestVectors.append(opInVec)
    
    resultTestVectors = genResultVectors(duv, opTestVectors)
    
    # Start the clock and reset the core
    cocotb.start_soon(Clock(duv.clk, 10, units="ns").start())
    await tb.reset()

    # Send test vectors to the DUV via the agent
    await tb.sendVectors(opTestVectors, resultTestVectors)

@cocotb.test()
async def randomBinaryTest(duv):
    log = logging.getLogger("cocotb.tb")
    log.setLevel(logging.DEBUG)

    numTests = 1000
    random.seed(42)

    tb = FpMultiplierTestbench(duv, False)

    # Get DUV parameters
    mantissaBits = int(duv.MANTISSA_WIDTH.value)
    exponentBits = int(duv.EXPONENT_WIDTH.value)
    totalBits = 1 + exponentBits + mantissaBits

    log.info(f"Floating point format: FP{totalBits}(E{exponentBits}M{mantissaBits})")

    # Generate random binary test vectors
    opTestVectors = []
    for i in range(numTests):
        opA = random.getrandbits(totalBits)
        opB = random.getrandbits(totalBits)
        opInVec = FpMultiplierOperandInputTransaction(opA, opB)

        opTestVectors.append(opInVec)

    resultTestVectors = genResultVectors(duv, opTestVectors)

    # Start the clock and reset the core
    cocotb.start_soon(Clock(duv.clk, 10, units="ns").start())
    await tb.reset()

    # Send test vectors to the DUV via the agent
    await tb.sendVectors(opTestVectors, resultTestVectors)

@cocotb.test()
async def randomFloatTest(duv):
    log = logging.getLogger("cocotb.tb")
    log.setLevel(logging.DEBUG)

    numTests = 1000
    random.seed(1234)

    tb = FpMultiplierTestbench(duv, False)

    # Get DUV parameters
    mantissaBits = int(duv.MANTISSA_WIDTH.value)
    exponentBits = int(duv.EXPONENT_WIDTH.value)
    totalBits = 1 + exponentBits + mantissaBits

    log.info(f"Floating point format: FP{totalBits}(E{exponentBits}M{mantissaBits})")

    # Generate random float test vectors
    opTestVectors = []
    for i in range(numTests):
        a = np.float32(random.uniform(-1, 1) * np.finfo(np.float32).max)
        b = np.float32(random.uniform(-1, 1) * np.finfo(np.float32).max)

        fpA = FloatingPoint.FloatingPoint.fromFloat32(a)
        fpB = FloatingPoint.FloatingPoint.fromFloat32(b)

        opInVec = FpMultiplierOperandInputTransaction(fpA.getBinary(), fpB.getBinary())
        opTestVectors.append(opInVec)
    
    resultTestVectors = genResultVectors(duv, opTestVectors)

    # Start the clock and reset the core
    cocotb.start_soon(Clock(duv.clk, 10, units="ns").start())
    await tb.reset()

    # Send test vectors to the DUV via the agent
    await tb.sendVectors(opTestVectors, resultTestVectors)

@cocotb.test()
async def specialValuesTest(duv):
    log = logging.getLogger("cocotb.tb")
    log.setLevel(logging.DEBUG)

    tb = FpMultiplierTestbench(duv, False)

    # Get DUV parameters
    mantissaBits = int(duv.MANTISSA_WIDTH.value)
    exponentBits = int(duv.EXPONENT_WIDTH.value)
    totalBits = 1 + exponentBits + mantissaBits

    log.info(f"Floating point format: FP{totalBits}(E{exponentBits}M{mantissaBits})")

    # Prepare special value test vectors
    fpZero = np.float32(0)
    fpOne = np.float32(1)

    specialFpValues = [
        np.float32(0.0),    # 0
        np.float32(-0.0),
        np.float32(1.0),    # 1
        np.float32(-1.0),
        np.float32(np.nextafter(fpZero, np.inf)),    # +denorm min
        np.float32(np.nextafter(fpZero, -np.inf)),   # -denorm min
        np.float32(np.finfo(np.float32).tiny),  # +norm min
        np.float32(-np.finfo(np.float32).tiny), # -norm min
        np.float32(np.finfo(np.float32).max),   # +norm max
        np.float32(-np.finfo(np.float32).max),  # -norm max
        np.float32(np.inf), # +inf
        np.float32(-np.inf), # -inf
        np.float32(np.nan), # NaN
        np.float32(np.nextafter(fpOne, np.inf)),  # 1 + epsilon
        np.float32(np.nextafter(fpOne, -np.inf)), # 1 - epsilon
    ]

    opTestVectors = []
    for a in specialFpValues:
        for b in specialFpValues:
            fpA = FloatingPoint.FloatingPoint.fromFloat32(a)
            fpB = FloatingPoint.FloatingPoint.fromFloat32(b)
            opInVec = FpMultiplierOperandInputTransaction(fpA.getBinary(), fpB.getBinary())
            opTestVectors.append(opInVec)

    resultTestVectors = genResultVectors(duv, opTestVectors)

    # Start the clock and reset the core
    cocotb.start_soon(Clock(duv.clk, 10, units="ns").start())
    await tb.reset()

    # Send test vectors to the DUV via the agent
    await tb.sendVectors(opTestVectors, resultTestVectors)

# Parameterized test with different formats
# Format   | Mantissa Bits | Exponent Bits
# ----------------------------------------
# FP32     | 23            | 8
# FP16     | 10            | 5
# BF16     | 7             | 8
# FP8 E4M3 | 3             | 4
# FP8 E5M2 | 2             | 5
# @pytest.mark.parameterize("fpFormat", [(23, 8), (10, 5), (7, 8), (3, 4), (2, 5)])
# def testFpAdder(fpFormat):
#     parameters = {
#         "MANTISSA_BITS": fpFormat[0],
#         "EXPONENT_BITS": fpFormat[1],
#     }
#
#     pass
