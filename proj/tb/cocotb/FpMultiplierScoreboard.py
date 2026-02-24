import cocotb.result
from cocotb.queue import Queue

from FpMultiplierTransactions import FpMultiplierResultOutputTransaction
from FloatingPoint import FloatingPoint

class FpMultiplierScoreboard:
    def __init__(self):
        self.expectedQueue = Queue()

    async def pushExpected(self, item):
        await self.expectedQueue.put(item)

    async def pushExpectedVectors(self, items: list):
        for item in items:
            await self.expectedQueue.put(item)

    async def checkOne(self, actual : FpMultiplierResultOutputTransaction):
        if self.expectedQueue.empty():
            raise cocotb.result.TestFailure("Unexpected output received with empty expected queue")

        fpA : FloatingPoint
        fpB : FloatingPoint
        fpExpected : FloatingPoint
        fpA, fpB, fpExpected = await self.expectedQueue.get()
        expectedValue = fpExpected.getBinary()
        actualValue = actual.result

        actException = int(actual.exception)
        actIsNaN = int(actual.isNaN)
        actIsInf = int(actual.isInf)

        # Convert to float for better error message
        fpActual = FloatingPoint(fpExpected.M, fpExpected.E, actualValue)
        
        # Generate test string for error
        fomularStr = f"{fpA.toFloatString()} x {fpB.toFloatString()} "
        binaryStr = f"expected {fpExpected.toFloatString()}, actual {fpActual.toFloatString()}"

        # Check the result
        assert expectedValue == actualValue, fomularStr + binaryStr
        
        # Check the exception flags
        expectedNaN = 1 if fpExpected.isNaN() else 0
        expectedInf = 1 if fpExpected.isInfinity() else 0
        expectedException = 1 if expectedNaN or expectedInf else 0

        assert expectedNaN == actIsNaN, fomularStr + binaryStr + f" exp/act NaN = {expectedNaN}/{actIsNaN}"
        assert expectedInf == actIsInf, fomularStr + binaryStr + f" exp/act Inf = {expectedInf}/{actIsInf}"
        assert expectedException == actException
        


