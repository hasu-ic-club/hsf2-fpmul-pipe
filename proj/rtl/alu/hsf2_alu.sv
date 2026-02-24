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
// FILE NAME: hsf2_alu.sv
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
// PURPOSE: Arithmetic logic unit (stage) for pipelined floating point multiplier
//
//-------------------------------------------------------------------------
// PARAMETERS:
// PARAMETER NAME      RANGE       DESCRIPTION                 DEFAULT VALUE
// EXPONENT_WIDTH      1-32        Bit width of exponent       8
// MANTISSA_WIDTH      1-128       Bit width of mantissa       23
//-FHDR--------------------------------------------------------------------

`include "hs_ifr_global.svh"
`include "hsf2_macros.svh"

`ifndef USE_DEFAULT_NETTYPE_WIRE
`default_nettype none
`else
`default_nettype wire
`endif

// Arithmetic logic unit (stage) for pipelined floating point multiplier
module hsf2_alu
import hsf2_typedef_pkg::*;
#(
    parameter int EXPONENT_WIDTH = 8,
    parameter int MANTISSA_WIDTH = 23,
    `LP_MODULE int OP_WIDTH       = 1 + EXPONENT_WIDTH + MANTISSA_WIDTH,
    `LP_MODULE int LZC_WIDTH      = $clog2(MANTISSA_WIDTH + 1 + 1),
    `LP_MODULE int REXP_WIDTH     = hs_math_basic_pkg::max(EXPONENT_WIDTH, LZC_WIDTH) + 1,
    `LP_MODULE int REXP_SUM_WIDTH = REXP_WIDTH + 2
)
(
    // Input operands
    input  logic       [OP_WIDTH - 1:0]           op_a_in,
    input  logic       [OP_WIDTH - 1:0]           op_b_in,

    // Output
    output logic       [MANTISSA_WIDTH + 1 - 1:0] prod_mant_out,
    output logic       [REXP_SUM_WIDTH - 1:0]     prod_exp_out,

    output alu_flags_s                            flags_out
);

`HSF2_MANTISSA_TYPEDEF(MANTISSA_WIDTH);
`HSF2_EXPONENT_TYPEDEF(EXPONENT_WIDTH);
`HSF2_FP_TYPEDEF(EXPONENT_WIDTH, MANTISSA_WIDTH);

`HSF2_EXT_MANT_TYPEDEF(MANTISSA_WIDTH);
`HSF2_PROD_MANT_TYPEDEF(MANTISSA_WIDTH);

localparam                                  PROD_COUT_BIT     = $bits(fp_prod_mant_t) - 1;
localparam                                  PROD_EXT_MANT_MSB = PROD_COUT_BIT - 1;
localparam                                  PROD_GUARD_BIT    = PROD_EXT_MANT_MSB - $bits(fp_ext_mant_t);
localparam                                  PROD_ROUND_BIT    = PROD_GUARD_BIT - 1;
localparam                                  PROD_STICKY_MSB   = PROD_ROUND_BIT - 1;

typedef logic [LZC_WIDTH - 1:0] lzc_t;
typedef logic signed [REXP_WIDTH - 1:0] rexp_t;
typedef logic signed [REXP_SUM_WIDTH - 1:0] prod_rexp_t;

// FP format structure
fp_s                                        op_a_fp;
fp_s                                        op_b_fp;

// Special result flags (pre-determined by input operands)
logic                                       sr_pre_inf;
logic                                       sr_pre_zero;

// Extended mantissa
fp_ext_mant_t                               ext_mant_a;
fp_ext_mant_t                               ext_mant_b;

// Denormalized number flag
logic                                       op_a_denorm;
logic                                       op_b_denorm;

// LZC of mantissa of de-normalized numbers
lzc_t                                       lzc_mant_a;
lzc_t                                       lzc_mant_b;

// Force normalized (extended exponent) mantissa
fp_ext_mant_t                               frcn_mant_a;
fp_ext_mant_t                               frcn_mant_b;

// Product result (full product)
fp_prod_mant_t                              prod_mant;

// Real exponent
rexp_t                                      rexp_a;
rexp_t                                      rexp_b;

// Real exponent summary
prod_rexp_t                                 prod_exp;
logic                                       prod_ovfl;
logic                                       prod_udfl;

// Assign input operators to FP format
assign op_a_fp                        = fp_s'(op_a_in);
assign op_b_fp                        = fp_s'(op_b_in);

// Special result generator for NaN/infinity/zero values
// Sideband for denorm numbers and result sign
hsf2_sp_result_gen #(
    .EXPONENT_WIDTH(EXPONENT_WIDTH),
    .MANTISSA_WIDTH(MANTISSA_WIDTH)
)
sp_result_gen_inst
(
    .op_a_in    (op_a_in              ),
    .op_b_in    (op_b_in              ),
    .result_nan (flags_out.result_nan ),
    .result_inf (sr_pre_inf           ),
    .result_zero(sr_pre_zero          ),
    .op_a_denorm(op_a_denorm          ),
    .op_b_denorm(op_b_denorm          ),
    .result_sign(flags_out.result_sign)
);

// Extend mantissa with hidden bit (for normalized numbers)
// or hidden bit = 0 (for de-normalized numbers)
assign ext_mant_a                     = {!op_a_denorm, op_a_fp.mantissa};
assign ext_mant_b                     = {!op_b_denorm, op_b_fp.mantissa};

// Leading zero counter for de-normalized numbers
hsf2_hblzc
#(
    .DATA_WIDTH     ($bits(fp_ext_mant_t)),
    .LZC_BLOCK_WIDTH(4                   )
)
lzc_mant_a_inst
(
    .din(ext_mant_a),
    .lzc(lzc_mant_a)
);

hsf2_hblzc
#(
    .DATA_WIDTH     ($bits(fp_ext_mant_t)),
    .LZC_BLOCK_WIDTH(4                   )
)
lzc_mant_b_inst
(
    .din(ext_mant_b),
    .lzc(lzc_mant_b)
);

// Force normalized mantissa
// For numbers already normalized, we pass the extend mantissa
// For denormalized numbers, we pass left shifted mantissa which
//     set the MSB of mantissa to 1
hsf2_lshift
#(
    .DATA_WIDTH      ($bits(fp_ext_mant_t)),
    .SFT_AMOUNT_WIDTH($bits(lzc_t)        )
)
denorm_mant_a_lsft_inst
(
    .data_in (ext_mant_a ),
    .sft_in  (lzc_mant_a ),
    .data_out(frcn_mant_a)
);

hsf2_lshift
#(
    .DATA_WIDTH      ($bits(fp_ext_mant_t)),
    .SFT_AMOUNT_WIDTH($bits(lzc_t)        )
)
denorm_mant_b_lsft_inst
(
    .data_in (ext_mant_b ),
    .sft_in  (lzc_mant_b ),
    .data_out(frcn_mant_b)
);

// Core multiplier for mantissas
hsf2_cmul #(
    .DATA_WIDTH($bits(fp_ext_mant_t))
)
cmul_inst
(
    .op_a_in   (frcn_mant_a),
    .op_b_in   (frcn_mant_b),
    .result_out(prod_mant  )
);

// Assign result product mantissa, carry out and GRS bits
always_comb begin : prod_result_assign
    flags_out.prod_cout  = prod_mant[PROD_COUT_BIT];
    prod_mant_out        = prod_mant[PROD_EXT_MANT_MSB -: $bits(fp_ext_mant_t)];
    flags_out.grs.guard  = prod_mant[PROD_GUARD_BIT];
    flags_out.grs.round  = prod_mant[PROD_ROUND_BIT];
    flags_out.grs.sticky = |prod_mant[PROD_STICKY_MSB:0];
end : prod_result_assign

// The product result of two mantissas
// Because of both two mantissa are 'forced normalized',
// the format of each mantissa is 1.XXXXXXXX...
// So the product of these two mantissas is in range [1.XXXX..., 4.0000) (dec)
// i.e. the largest product should be less than 11.1111... (bin)
// and the smallest product should be 01.0000... (bin)
// So we do not need any left align, only right align needed

// Exponent extract
hsf2_exp_extract
#(
    .EXPONENT_WIDTH(EXPONENT_WIDTH),
    .LZC_WIDTH     (LZC_WIDTH     )
)
exp_a_extract_inst
(
    .exp_in   (op_a_fp.exp),
    .denorm_in(op_a_denorm),
    .lzc_in   (lzc_mant_a ),
    .real_exp (rexp_a     )
);

hsf2_exp_extract
#(
    .EXPONENT_WIDTH(EXPONENT_WIDTH),
    .LZC_WIDTH     (LZC_WIDTH     )
)
exp_b_extract_inst
(
    .exp_in   (op_b_fp.exp),
    .denorm_in(op_b_denorm),
    .lzc_in   (lzc_mant_b ),
    .real_exp (rexp_b     )
);

// Exponent summary
hsf2_exp_sum #(
    .MANTISSA_WIDTH(MANTISSA_WIDTH),
    .EXPONENT_WIDTH(EXPONENT_WIDTH),
    .REXP_WIDTH    (REXP_WIDTH    )
)
rexp_sum_inst
(
    .rexp_a_in(rexp_a   ),
    .rexp_b_in(rexp_b   ),
    .prod_exp (prod_exp ),
    .udfl     (prod_udfl),
    .ovfl     (prod_ovfl)
);

assign prod_exp_out                   = prod_exp;

// Special value flags
assign flags_out.result_inf           = prod_ovfl || sr_pre_inf;
assign flags_out.result_zero          = prod_udfl || sr_pre_zero;

endmodule : hsf2_alu