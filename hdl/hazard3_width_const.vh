// These really ought to be localparams, but are occasionally needed for
// passing flags around between modules, so are made available as parameters
// instead. It's ugly, but better scope hygiene than the preprocessor. These
// parameters should not be changed from their default values.

parameter W_REGADDR = 5,

parameter W_ALUOP   = 6,
parameter W_ALUSRC  = 1,
parameter W_MEMOP   = 5,
parameter W_BCOND   = 2,
parameter W_SHAMT   = 5,

parameter W_EXCEPT  = 4,
parameter W_MULOP   = 3
