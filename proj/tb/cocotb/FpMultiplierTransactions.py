class FpMultiplierOperandInputTransaction:
    def __init__(self, op_a, op_b):
        self.op_a = op_a
        self.op_b = op_b

    def as_tuple(self):
        return self.op_a, self.op_b


class FpMultiplierResultOutputTransaction:
    def __init__(self, result, exception=None, is_nan=None, is_inf=None):
        self.result = result
        self.exception = exception
        self.isNaN = is_nan
        self.isInf = is_inf

    def as_tuple(self):
        return self.result, self.isNaN, self.isInf, self.exception
