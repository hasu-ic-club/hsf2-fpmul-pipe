//+FHDR--------------------------------------------------------------------
// Copyright (C) 2025 Hasunosora IC Design Club
// MIT License
// Permission is hereby granted, free of charge, to any person obtaining a 
// copy of this design and associated documentation files (the “Design”), 
// to deal in the Design without restriction, including without limitation 
// the rights to use, copy, modify, merge, publish, distribute, sublicense, 
// and/or sell copies of the Design, and to permit persons to whom the 
// Design is furnished to do so, subject to the following conditions:
// The above copyright notice and this permission notice shall be included 
// in all copies or substantial portions of the Design.
//
// THE DESIGN IS PROVIDED “AS IS”, WITHOUT WARRANTY OF ANY KIND, 
// EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF 
// MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. 
// IN NO EVENT SHALL THE AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, 
// DAMAGES OR OTHER LIABILITY, WHETHER IN AN ACTION OF CONTRACT, 
// TORT OR OTHERWISE, ARISING FROM, OUT OF OR IN CONNECTION WITH THE 
// DESIGN OR THE USE OR OTHER DEALINGS IN THE DESIGN.
//-------------------------------------------------------------------------
// FILE NAME: hsf2_exp_sum.sv
// AUTHOR:    Onodera Tsusaki
// EMAIL:     apertureelectronic@outlook.com
//-------------------------------------------------------------------------
// RELEASE VERSION: 0.1a0
// VERSION DESCRIPTION: First Edition
//-------------------------------------------------------------------------
// RELEASES:
// VERSION    AUTHOR        RELEASE DATE  DESCRIPTION
// 0.1a0      O. Tsusaki    2025/12/2     First Edition
//-------------------------------------------------------------------------
// PURPOSE: Exponent summary (signed real exponent) for floating-point multiplier
//
//-------------------------------------------------------------------------
// PARAMETERS:
// PARAMETER NAME  RANGE           DESCRIPTION                 DEFAULT VALUE
// EXPONENT_WIDTH  1-32            Exponent bit width          8
// MANTISSA_WIDTH  1-128           Mantissa bit width          23
// REXP_WIDTH      1-33            Signed real exponent width  9
//-FHDR--------------------------------------------------------------------

`include "hs_ifr_global.svh"

`ifndef USE_DEFAULT_NETTYPE_WIRE
`default_nettype none
`else
`default_nettype wire
`endif

// Exponent summary (signed real exponent) for floating-point multiplier
module hsf2_exp_sum
#(
    parameter  int MANTISSA_WIDTH = 23,
    parameter  int EXPONENT_WIDTH = 8,
    parameter  int REXP_WIDTH     = 9,
    `LP_MODULE int EXP_SUM_WIDTH = REXP_WIDTH + 2
)
(
    input  logic signed [REXP_WIDTH - 1:0]    rexp_a_in,
    input  logic signed [REXP_WIDTH - 1:0]    rexp_b_in,

    output logic signed [EXP_SUM_WIDTH - 1:0] prod_exp,
    output logic                              udfl,
    output logic                              ovfl
);

typedef logic signed [EXP_SUM_WIDTH - 1:0] sexp_t;

sexp_t offset;      // Constant offset

sexp_t rexp_a;
sexp_t rexp_b;
sexp_t prod_exp_int;

sexp_t udfl_bound;  // Underflow bound, if result's exponent less than this ties it to 0
sexp_t ovfl_bound;  // Overflow bound, if result's exponent greater than this ties it to infinity

// Extend the signed exponent
assign offset       = sexp_t'((1 << (EXPONENT_WIDTH - 1)) - 1);
assign rexp_a       = sexp_t'(rexp_a_in);
assign rexp_b       = sexp_t'(rexp_b_in);

// Product exponent = expA + expB - offset
assign prod_exp_int = rexp_a + rexp_b - offset;
assign prod_exp     = prod_exp_int;

// Underflow / overflow check
assign udfl_bound   = -(MANTISSA_WIDTH + 1);
assign ovfl_bound   = (1 << EXPONENT_WIDTH) - 2;

assign udfl         = prod_exp_int < udfl_bound;
assign ovfl         = prod_exp_int > ovfl_bound;

endmodule : hsf2_exp_sum