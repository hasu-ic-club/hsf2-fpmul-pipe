class FpMultiplierOperandInputTransaction:
    def __init__(self, operandA, operandB):
        self.operandA = operandA
        self.operandB = operandB

class FpMultiplierResultOutputTransaction:
    def __init__(self, result, exception=None, isNaN=None, isInf=None):
        self.result = result
        self.exception = exception
        self.isNaN = isNaN
        self.isInf = isInf