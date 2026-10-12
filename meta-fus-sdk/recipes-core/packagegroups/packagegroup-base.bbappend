# meta-rauc pulls rauc into the base packagegroup wherever the distro carries
# "rauc"; keep it out wherever the update framework is not in effect.
RDEPENDS:packagegroup-base-rauc:fus-no-update = ""
