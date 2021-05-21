// These really ought to be localparams, but are occasionally needed for
// passing flags around between modules, so are made available as parameters
// instead. It's ugly, but better scope hygiene than the preprocessor. These
// parameters should not be changed from their default values.

parameter W_REGADDR = 5,

parameter W_ALUOP   = 4,
parameter W_ALUSRC  = 2,
parameter W_MEMOP   = 4,
parameter W_BCOND   = 2,

parameter W_EXCEPT  = 3,
parameter W_MULOP   = 3
