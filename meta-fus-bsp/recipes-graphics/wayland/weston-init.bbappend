# The i.MX6SX can either use the 2D or 3D GPU
# and we configure the 3D GPU by default in the DTS
# so disable g2d support in weston by default.

INI_UNCOMMENT_USE_G2D:fsimx6sx = ""
