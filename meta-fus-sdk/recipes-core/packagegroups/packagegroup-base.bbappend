# meta-rauc pulls rauc into the base packagegroup wherever the distro carries
# "rauc"; keep it out of machines without A/B in effect.
RDEPENDS:packagegroup-base-rauc:fus-no-ab = ""
