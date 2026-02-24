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
// FILE NAME: hsf2_postproc.sv
// AUTHOR:    Onodera Tsusaki
// EMAIL:     apertureelectronic@outlook.com
//-------------------------------------------------------------------------
// RELEASE VERSION: 0.1a0
// VERSION DESCRIPTION: First Edition
//-------------------------------------------------------------------------
// RELEASES:
// VERSION    AUTHOR        RELEASE DATE  DESCRIPTION
// 0.1a0      O. Tsusaki    2025/12/3     First Edition
//-------------------------------------------------------------------------
// PURPOSE: Postprocess stage of pipelined floating point multiplier
//
//-------------------------------------------------------------------------
// PARAMETERS:
// PARAMETER NAME  RANGE           DESCRIPTION             DEFAULT VALUE
// EXPONENT_WIDTH  1-32            Exponent bit width      8
// MANTISSA_WIDTH  1-128           Mantissa bit width      23
// FP_ROUND_MOD    fp_round_mode_s Floating point rounding FP_ROUND_MODE_TIES_TO_EVEN
//                                 mode
//-FHDR--------------------------------------------------------------------

`include "hs_ifr_global.svh"
`include "hsf2_macros.svh"

`ifndef USE_DEFAULT_NETTYPE_WIRE
`default_nettype none
`else
`default_nettype wire
`endif

// Postprocess stage of pipelined floating point multiplier
module hsf2_postproc
import hsf2_typedef_pkg::*;
#(
    parameter int             EXPONENT_WIDTH = 8,
    parameter int             MANTISSA_WIDTH = 23,
    parameter fp_round_mode_s FP_ROUND_MODE  = FP_ROUND_MODE_TIES_TO_EVEN,
    `LP_MODULE int OP_WIDTH  = 1 + EXPONENT_WIDTH + MANTISSA_WIDTH
)
(
    // Result under process input
    input  logic             [MANTISSA_WIDTH + 1 - 1:0] mant_in,
    input  logic             [EXPONENT_WIDTH - 1:0]     exp_in,

    // Flags
    input  renorm_flags_s                               flags_in,

    // Output
    output logic             [OP_WIDTH - 1:0]           result_out,
    output exception_flags_s                            exception_out
);

`HSF2_FP_TYPEDEF(EXPONENT_WIDTH, MANTISSA_WIDTH);
`HSF2_MANTISSA_TYPEDEF(MANTISSA_WIDTH);
`HSF2_EXPONENT_TYPEDEF(EXPONENT_WIDTH);
`HSF2_EXT_MANT_TYPEDEF(MANTISSA_WIDTH);

localparam    fp_exp_t MAX_EXPONENT     = {EXPONENT_WIDTH{1'b1}};          // Exponent all 1 (overflowed)
localparam    fp_exp_t EDGE_EXPONENT    = MAX_EXPONENT - 1;                // This is the real valid maximum exponent


// Rounded mantissa
fp_ext_mant_t          rnd_mant;
logic                  rnd_cout;

// Final result
fp_mant_t              result_mant;
fp_exp_t               result_exp;
logic                  final_rnd_to_inf;

fp_s                   result_fp;

// GRS rounding
hsf2_grs_round
#(
    .MANTISSA_WIDTH(MANTISSA_WIDTH),
    .FP_ROUND_MODE (FP_ROUND_MODE )
)
grs_round_inst
(
    .sign_in     (flags_in.result_sign),
    .ext_mant_in (mant_in             ),
    .grs_in      (flags_in.grs        ),
    .rnd_mant_out(rnd_mant            ),
    .rnd_cout    (rnd_cout            )
);

// Final realign / fix
always_comb begin : final_fix
    if (rnd_cout) begin
        // Round and overflow to next exponent
        if (exp_in == EDGE_EXPONENT) begin
            // Overflow to infinity
            result_exp       = MAX_EXPONENT;
            result_mant      = '0;
            final_rnd_to_inf = '1;
        end
        else begin
            result_exp       = exp_in + 'd1;                    // Right shift for re-align
            result_mant      = rnd_mant[1 +: $bits(fp_mant_t)]; // Right shift 1 bit and hidden bit truncate
            final_rnd_to_inf = '0;
        end
    end
    else if (rnd_mant[$bits(fp_mant_t)] && (~|exp_in)) begin
        // A denormalized number overflowed to normalized
        result_exp       = EXPONENT_WIDTH'(1);
        result_mant      = rnd_mant[0 +: $bits(fp_mant_t)]; // Hidden bit truncate
        final_rnd_to_inf = '0;
    end
    else begin
        // Normal
        result_exp       = exp_in;
        result_mant      = rnd_mant[0 +: $bits(fp_mant_t)]; // Hidden bit truncate
        final_rnd_to_inf = '0;
    end
end : final_fix

// Result output
always_comb begin : result_mux
    if (flags_in.result_nan) begin
        // Generate a NaN number
        result_fp.sign        = '0;
        result_fp.mantissa    = $bits(fp_mant_t)'(1);
        result_fp.exp         = MAX_EXPONENT;
    end
    else if (flags_in.result_inf) begin
        result_fp.sign        = flags_in.result_sign;
        result_fp.mantissa    = '0;
        result_fp.exp         = MAX_EXPONENT;
    end
    else begin
        result_fp.sign        = flags_in.result_sign;
        result_fp.mantissa    = result_mant;
        result_fp.exp         = result_exp;
    end
end : result_mux

assign result_out        = result_fp;

// Exception flags output
assign exception_out.nan = flags_in.result_nan;
assign exception_out.inf = !flags_in.result_nan && (flags_in.result_inf || final_rnd_to_inf);

endmodule : hsf2_postproc