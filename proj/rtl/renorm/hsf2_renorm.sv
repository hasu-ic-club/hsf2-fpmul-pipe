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
// FILE NAME: hsf2_renorm.sv
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
// PURPOSE: Re-normalize stage for pipelined floating point multiplier
//
//-------------------------------------------------------------------------
// PARAMETERS:
// PARAMETER NAME      RANGE       DESCRIPTION                 DEFAULT VALUE
// N/A
//-FHDR--------------------------------------------------------------------

`include "hs_ifr_global.svh"
`include "hsf2_macros.svh"

`ifndef USE_DEFAULT_NETTYPE_WIRE
`default_nettype none
`else
`default_nettype wire
`endif

// Re-normalize stage for pipelined floating point multiplier
module hsf2_renorm
import hsf2_typedef_pkg::*;
#(
    parameter  int EXPONENT_WIDTH = 8,
    parameter  int MANTISSA_WIDTH = 23,
    `LP_MODULE int LZC_WIDTH      = $clog2(MANTISSA_WIDTH + 1 + 1),
    `LP_MODULE int REXP_WIDTH     = hs_math_basic_pkg::max(EXPONENT_WIDTH, LZC_WIDTH) + 1,
    `LP_MODULE int REXP_SUM_WIDTH = REXP_WIDTH + 2
)
(
    // Input
    input  logic          [MANTISSA_WIDTH + 1 - 1:0] prod_mant_in,
    input  logic          [REXP_SUM_WIDTH - 1:0]     prod_exp_in,

    input  alu_flags_s                               flags_in,

    // Output
    output logic          [MANTISSA_WIDTH + 1 - 1:0] mant_result_out,
    output logic          [EXPONENT_WIDTH - 1:0]     exp_result_out,

    output renorm_flags_s                            flags_out
);

`HSF2_EXT_MANT_TYPEDEF(MANTISSA_WIDTH);
`HSF2_EXPONENT_TYPEDEF(EXPONENT_WIDTH);
typedef logic signed [REXP_SUM_WIDTH - 1:0] rexp_t;
typedef logic [REXP_SUM_WIDTH - 1 - 1:0]    urexp_t;

localparam      fp_exp_t MAX_EXPONENT        = {EXPONENT_WIDTH{1'b1}};          // Exponent all 1 (overflowed)
localparam      fp_exp_t EDGE_EXPONENT       = MAX_EXPONENT - 1;                // This is the real valid maximum exponent
localparam      rexp_t   EDGE_REXP           = rexp_t'({1'b0, EDGE_EXPONENT});

typedef struct packed
{
    logic         carry_out;
    fp_ext_mant_t ext_mant;
} fp_carry_mant_t;

// Normalization overflow flag (carry out)
logic                    norm_ovfl;
logic                    rexp_at_edge;
logic                    ovfl_to_inf;
rexp_t                   rexp_carried;

// Right normalization (right shift)
logic                    result_denorm;
urexp_t                  rsft_amount;                                           // Total right shift amount
fp_carry_mant_t          carry_mant_rsft_in;
fp_carry_mant_t          carry_mant_rsft_out;
fp_ext_mant_t            mant_ralign;
grs_s                    grs_ralign;

// Result exponent (unsigned, offseted)
fp_exp_t                 result_exp;

// Normalization overflow detection
//  If the product has a carry out, we should right shift the mantissa 1 bit,
//  and increase the result exponent
//  Note: If the result exponent is already the EDGE_EXPONENT, the result will
//        overflow to infinity
assign norm_ovfl                    = flags_in.prod_cout;
assign rexp_at_edge                 = prod_exp_in == EDGE_REXP;
assign ovfl_to_inf                  = norm_ovfl && rexp_at_edge;
assign rexp_carried                 = prod_exp_in + (norm_ovfl ? rexp_t'('sd1) : rexp_t'('sd0));

// Right normalization
//  1. If the result has carry out, we need right shift 1 bit for normalization
//  2. If the product exponent < 1, we need to right shift the mantissa to set a
//     de-normalized number
assign result_denorm                = rexp_carried < 'sd1;

always_comb begin : rsft_amount_dete
    unique case ({result_denorm, norm_ovfl})
        2'b11: rsft_amount = urexp_t'(-rexp_carried + 'sd1 + 'sd1); // Right shift 1 bit + exponent + 1
        2'b10: rsft_amount = urexp_t'(-rexp_carried + 'sd1);        // Right shift exponent + 1
        2'b01: rsft_amount = urexp_t'('sd1);                        // Right shift 1 bit
        2'b00: rsft_amount = '0;
    endcase
end : rsft_amount_dete

// Right shifter
assign carry_mant_rsft_in.carry_out = flags_in.prod_cout;
assign carry_mant_rsft_in.ext_mant  = prod_mant_in;

hsf2_grs_rshift #(
    .DATA_WIDTH      ($bits(fp_carry_mant_t)),
    .SFT_AMOUNT_WIDTH($bits(urexp_t)        )
)
grs_rshift_inst
(
    .grs_in  (flags_in.grs       ),
    .data_in (carry_mant_rsft_in ),
    .sft_in  (rsft_amount        ),
    .data_out(carry_mant_rsft_out),
    .grs_out (grs_ralign         )
);

assign mant_ralign                  = carry_mant_rsft_out.ext_mant;

// Result exponent
assign result_exp                   = (rexp_carried < 'sd1) ? '0 : fp_exp_t'(rexp_carried[$bits(fp_exp_t) - 1:0]);

// Sign, mantissa and exponent output
always_comb begin : sp_value_out
    if (flags_in.result_zero) begin
        flags_out.result_sign = '0;
        mant_result_out       = '0;
        exp_result_out        = '0;
    end
    else begin
        flags_out.result_sign = flags_in.result_sign;
        mant_result_out       = mant_ralign;
        exp_result_out        = result_exp;
    end
end : sp_value_out

// GRS flags output
always_comb begin : grs_out
    if (flags_in.result_zero || flags_in.result_nan || flags_in.result_inf) begin
        flags_out.grs = '0;
    end
    else begin
        flags_out.grs = grs_ralign;
    end
end : grs_out

// Flags output
assign flags_out.result_inf         = flags_in.result_inf || ovfl_to_inf;
assign flags_out.result_nan         = flags_in.result_nan;

endmodule : hsf2_renorm