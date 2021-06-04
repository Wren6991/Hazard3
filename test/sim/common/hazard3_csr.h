#ifndef _HAZARD3_CSR_H
#define _HAZARD3_CSR_H

#define hazard3_csr_midcr 0xbc0
#define hazard3_csr_meie0 0xbe0 // External interrupt enable IRQ0 -> 31
#define hazard3_csr_meip0 0xfe0 // External interrupt pending IRQ0 -> 31
#define hazard3_csr_mlei  0xfe4 // Lowest external interrupt (pending & enabled)

#endif
