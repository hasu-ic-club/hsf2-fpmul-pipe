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
// FILE NAME: hsf2_fpmul_pipe.sv
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
// PURPOSE: Pipelined floating-point multiplier
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

module hsf2_fpmul_pipe
import hs_ifr_misc_typedefs_pkg::*;
import hsf2_typedef_pkg::*;
#(
    parameter int             EXPONENT_WIDTH = 8,
    parameter int             MANTISSA_WIDTH = 23,
    parameter fp_round_mode_s FP_ROUND_MODE  = FP_ROUND_MODE_TIES_TO_EVEN,
    `LP_MODULE int OP_WIDTH = 1 + EXPONENT_WIDTH + MANTISSA_WIDTH
)
(
    // Clock & reset
    input  logic                  clk,
    input  logic                  aresetn,

    // Operators input (handshake)
    input  logic [OP_WIDTH - 1:0] op_a_in,
    input  logic [OP_WIDTH - 1:0] op_b_in,
    input  logic                  op_valid,
    output logic                  op_ready,

    // Result output (handshake)
    output logic [OP_WIDTH - 1:0] result_out,
    output logic                  result_valid,
    input  logic                  result_ready,

    // Exception output (sync with result)
    output logic                  exception_out,    // Indicate the result has exception value (NaN/overflow)
    output logic                  nan_out,          // Indicate the result is NaN
    output logic                  inf_out           // Indicate the result is infinite (overflow)
);

`HSF2_FP_TYPEDEF(EXPONENT_WIDTH, MANTISSA_WIDTH);

`HSF2_MANTISSA_TYPEDEF(MANTISSA_WIDTH);
`HSF2_EXPONENT_TYPEDEF(EXPONENT_WIDTH);

`HSF2_EXT_MANT_TYPEDEF(MANTISSA_WIDTH);

localparam           int LZC_WIDTH                = $clog2(MANTISSA_WIDTH + 1 + 1);
localparam           int REXP_WIDTH               = hs_math_basic_pkg::max(EXPONENT_WIDTH, LZC_WIDTH) + 1;
localparam           int REXP_SUM_WIDTH           = REXP_WIDTH + 2;

typedef logic signed [REXP_SUM_WIDTH - 1:0] prod_rexp_t;

// Packed structures for inter-stage data path
typedef struct packed
{
    fp_ext_mant_t mant_prod;
    prod_rexp_t   rexp_prod;
    alu_flags_s   flags;
} alu_renorm_dp_s;

typedef struct packed
{
    fp_ext_mant_t  mant_result;
    fp_exp_t       exp_result;
    renorm_flags_s flags;
} renorm_postproc_dp_s;

typedef struct packed
{
    fp_s              result;
    exception_flags_s exception_flags;
} postproc_out_dp_s;

// Inter-stage handshake
logic                    alu_renorm_hs_valid;
logic                    alu_renorm_hs_ready;

logic                    renorm_postproc_hs_valid;
logic                    renorm_postproc_hs_ready;

// Inter-stage data path
alu_renorm_dp_s          alu_out;
alu_renorm_dp_s          renorm_in;

renorm_postproc_dp_s     renorm_out;
renorm_postproc_dp_s     postproc_in;

postproc_out_dp_s        postproc_out;
postproc_out_dp_s        output_dp;

// Stage I: ALU stage
hsf2_alu #(
    .EXPONENT_WIDTH(EXPONENT_WIDTH),
    .MANTISSA_WIDTH(MANTISSA_WIDTH)
)
alu_inst (
    .op_a_in      (op_a_in          ),
    .op_b_in      (op_b_in          ),
    .prod_mant_out(alu_out.mant_prod),
    .prod_exp_out (alu_out.rexp_prod),
    .flags_out    (alu_out.flags    )
);

// Pipeline slice between ALU and re-norm
hs_dpath_skid_buffer
#(
    .FULL_THROUGHPUT(BOOL_TRUE             ),
    .CTRL_PIPE      (BOOL_FALSE            ),
    .DATA_PIPE      (BOOL_TRUE             ),
    .STROBE_UNIT    ($bits(alu_renorm_dp_s)),
    .DATA_TYPE      (alu_renorm_dp_s       )
)
alu_renorm_pipe_inst
(
    .clk       (clk                ),
    .aresetn   (aresetn            ),
    .in_data   (alu_out            ),
    .in_valid  (op_valid           ),
    .in_last   ('0                 ),
    .in_ready  (op_ready           ),
    .in_strobe ('0                 ),
    .out_data  (renorm_in          ),
    .out_valid (alu_renorm_hs_valid),
    .out_last  (                   ),
    .out_ready (alu_renorm_hs_ready),
    .out_strobe(                   )
);

// Stage II: Re-normalization
hsf2_renorm #(
    .EXPONENT_WIDTH(EXPONENT_WIDTH),
    .MANTISSA_WIDTH(MANTISSA_WIDTH)
)
renorm_inst
(
    .prod_mant_in   (renorm_in.mant_prod   ),
    .prod_exp_in    (renorm_in.rexp_prod   ),
    .flags_in       (renorm_in.flags       ),
    .mant_result_out(renorm_out.mant_result),
    .exp_result_out (renorm_out.exp_result ),
    .flags_out      (renorm_out.flags      )
);

// Pipeline slice between re-norm and postproc
hs_dpath_skid_buffer
#(
    .FULL_THROUGHPUT(BOOL_TRUE                  ),
    .CTRL_PIPE      (BOOL_FALSE                 ),
    .DATA_PIPE      (BOOL_TRUE                  ),
    .STROBE_UNIT    ($bits(renorm_postproc_dp_s)),
    .DATA_TYPE      (renorm_postproc_dp_s       )
)
renorm_postproc_pipe_inst
(
    .clk       (clk                     ),
    .aresetn   (aresetn                 ),
    .in_data   (renorm_out              ),
    .in_valid  (alu_renorm_hs_valid     ),
    .in_last   ('0                      ),
    .in_ready  (alu_renorm_hs_ready     ),
    .in_strobe ('0                      ),
    .out_data  (postproc_in             ),
    .out_valid (renorm_postproc_hs_valid),
    .out_last  (                        ),
    .out_ready (renorm_postproc_hs_ready),
    .out_strobe(                        )
);

// Stage III: Post-process
hsf2_postproc
#(
    .EXPONENT_WIDTH(EXPONENT_WIDTH),
    .MANTISSA_WIDTH(MANTISSA_WIDTH),
    .FP_ROUND_MODE (FP_ROUND_MODE )
)
postproc_inst
(
    .mant_in      (postproc_in.mant_result     ),
    .exp_in       (postproc_in.exp_result      ),
    .flags_in     (postproc_in.flags           ),
    .result_out   (postproc_out.result         ),
    .exception_out(postproc_out.exception_flags)
);

// Pipeline slice between post-process and output
hs_dpath_skid_buffer
#(

    .FULL_THROUGHPUT(BOOL_TRUE               ),
    .CTRL_PIPE      (BOOL_FALSE              ),
    .DATA_PIPE      (BOOL_TRUE               ),
    .STROBE_UNIT    ($bits(postproc_out_dp_s)),
    .DATA_TYPE      (postproc_out_dp_s       )
)
postproc_out_pipe_inst
(
    .clk       (clk                     ),
    .aresetn   (aresetn                 ),
    .in_data   (postproc_out            ),
    .in_valid  (renorm_postproc_hs_valid),
    .in_last   ('0                      ),
    .in_ready  (renorm_postproc_hs_ready),
    .in_strobe ('0                      ),
    .out_data  (output_dp               ),
    .out_valid (result_valid            ),
    .out_last  (                        ),
    .out_ready (result_ready            ),
    .out_strobe(                        )
);

assign result_out    = output_dp.result;
assign exception_out = |output_dp.exception_flags;
assign nan_out       = output_dp.exception_flags.nan;
assign inf_out       = output_dp.exception_flags.inf;

endmodule : hsf2_fpmul_pipe