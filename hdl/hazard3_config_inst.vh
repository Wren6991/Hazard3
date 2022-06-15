/*****************************************************************************\
|                      Copyright (C) 2021-2022 Luke Wren                      |
|                     SPDX-License-Identifier: Apache-2.0                     |
\*****************************************************************************/

// Pass-through of parameters defined in hazard3_config.vh, so that these can
// be set at instantiation rather than editing the config file, and will flow
// correctly down through the hierarchy.

.RESET_VECTOR       (RESET_VECTOR),
.MTVEC_INIT         (MTVEC_INIT),
.EXTENSION_A        (EXTENSION_A),
.EXTENSION_C        (EXTENSION_C),
.EXTENSION_M        (EXTENSION_M),
.EXTENSION_ZBA      (EXTENSION_ZBA),
.EXTENSION_ZBB      (EXTENSION_ZBB),
.EXTENSION_ZBC      (EXTENSION_ZBC),
.EXTENSION_ZBS      (EXTENSION_ZBS),
.EXTENSION_ZBKB     (EXTENSION_ZBKB),
.EXTENSION_ZIFENCEI (EXTENSION_ZIFENCEI),
.CSR_M_MANDATORY    (CSR_M_MANDATORY),
.CSR_M_TRAP         (CSR_M_TRAP),
.CSR_COUNTER        (CSR_COUNTER),
.U_MODE             (U_MODE),
.PMP_REGIONS        (PMP_REGIONS),
.PMP_GRAIN          (PMP_GRAIN),
.PMP_HARDWIRED      (PMP_HARDWIRED),
.PMP_HARDWIRED_ADDR (PMP_HARDWIRED_ADDR),
.PMP_HARDWIRED_CFG  (PMP_HARDWIRED_CFG),
.DEBUG_SUPPORT      (DEBUG_SUPPORT),
.NUM_IRQ            (NUM_IRQ),
.MVENDORID_VAL      (MVENDORID_VAL),
.MIMPID_VAL         (MIMPID_VAL),
.MHARTID_VAL        (MHARTID_VAL),
.MCONFIGPTR_VAL     (MCONFIGPTR_VAL),
.REDUCED_BYPASS     (REDUCED_BYPASS),
.MULDIV_UNROLL      (MULDIV_UNROLL),
.MUL_FAST           (MUL_FAST),
.MULH_FAST          (MULH_FAST),
.FAST_BRANCHCMP     (FAST_BRANCHCMP),
.BRANCH_PREDICTOR   (BRANCH_PREDICTOR),
.MTVEC_WMASK        (MTVEC_WMASK),
.RESET_REGFILE      (RESET_REGFILE),
.W_ADDR             (W_ADDR),
.W_DATA             (W_DATA)
