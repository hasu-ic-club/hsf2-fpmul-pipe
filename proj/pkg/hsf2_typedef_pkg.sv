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
// FILE NAME: hsf2_typedef_pkg.sv
// AUTHOR:    Onodera Tsusaki
// EMAIL:     apertureelectronic@outlook.com
//-------------------------------------------------------------------------
// RELEASE VERSION: 0.2
// VERSION DESCRIPTION: Edition to fix corner case bugs.
//-------------------------------------------------------------------------
// RELEASES:
// VERSION    AUTHOR        RELEASE DATE  DESCRIPTION
// 0.1a0      O. Tsusaki    2025/12/2     First Edition
// 0.2        O. Tsusaki    2026/11/23    Add flag signal 'finite_overflow'
//                                        between renorm and post-proc stage.
//-------------------------------------------------------------------------
// PURPOSE: Type definitions for pipelined floating point multiplier
//
//-FHDR--------------------------------------------------------------------

`include "hs_ifr_global.svh"

`ifndef USE_DEFAULT_NETTYPE_WIRE
`default_nettype none
`else
`default_nettype wire
`endif

// Type definitions for pipelined floating point multiplier
package hsf2_typedef_pkg;
    typedef enum
    {
        FP_ROUND_MODE_TIES_TO_EVEN,
        FP_ROUND_MODE_TOWARD_ZERO,
        FP_ROUND_MODE_TOWARD_POSITIVE,
        FP_ROUND_MODE_TOWARD_NEGATIVE
    } fp_round_mode_s;

    typedef struct packed
    {
        logic guard;
        logic round;
        logic sticky;
    } grs_s;

    typedef struct packed
    {
        logic result_sign;
        logic result_inf;
        logic result_zero;
        logic result_nan;
        logic prod_cout;
        grs_s grs;
    } alu_flags_s;

    typedef struct packed
    {
        logic result_sign;
        logic result_inf;
        logic result_nan;
        logic finite_ovfl;
        grs_s grs;
    } renorm_flags_s;

    typedef struct packed
    {
        logic nan;
        logic inf;
    } exception_flags_s;
endpackage : hsf2_typedef_pkg