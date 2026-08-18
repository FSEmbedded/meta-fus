# machine-side enablement for the A/B update standard image on eMMC
# boards; pulled into the machine config via a single require line.
# declares a MACHINE_FEATURES flag.

# capability flag — query in recipes with bb.utils.contains
MACHINE_FEATURES:append = " fus-update-ab"

# runtime packages are image-scoped (fus-update.bbclass / the image
# recipes), not listed here.
