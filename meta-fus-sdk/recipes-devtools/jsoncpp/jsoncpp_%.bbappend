# fs-updater-lib links jsoncpp both ways depending on the component; build both.
EXTRA_OECMAKE += "-DBUILD_SHARED_LIBS=ON -DBUILD_STATIC_LIBS=ON -DJSONCPP_WITH_TESTS=OFF"
