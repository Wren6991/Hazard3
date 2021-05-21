// Pass-through of parameters defined in hazard5_config.vh, so that these can
// be set at instantiation rather than editing the config file, and will flow
// correctly down through the hierarchy.

.RESET_VECTOR    (RESET_VECTOR),
.MTVEC_INIT      (MTVEC_INIT),
.EXTENSION_C     (EXTENSION_C),
.EXTENSION_M     (EXTENSION_M),
.CSR_M_MANDATORY (CSR_M_MANDATORY),
.CSR_M_TRAP      (CSR_M_TRAP),
.CSR_COUNTER     (CSR_COUNTER),
.REDUCED_BYPASS  (REDUCED_BYPASS),
.MULDIV_UNROLL   (MULDIV_UNROLL),
.MUL_FAST        (MUL_FAST),
.MTVEC_WMASK     (MTVEC_WMASK),
.W_ADDR          (W_ADDR),
.W_DATA          (W_DATA)
