This README file contains information on the contents of the meta-fus layer.
'meta-fus' is for SOLDERCORE8ULP and compatible with the i.MX Linux Yocto Project BSP 6.1.1_1.0.0 Release (imx-linux-langdale).

Quick Start Guide with Yocto Project to build meta-fus:

Step 1:
    See the i.MX Yocto Project User's Guide for instructions on installing repo.
    (https://www.nxp.com/design/software/embedded-software/i-mx-software/embedded-linux-for-i-mx-applications-processors:IMXLINUX)

    3.2 Host packages (Quote from i.MX Yocto Project User's Guide.pdf page 6):

        A Yocto Project build requires that some packages be installed for the build that are documented under the
        Yocto Project. Go to Yocto Project Quick Start and check for the packages that must be installed for your build machine.

Step 2:
    3.3 Setting up the Repo utility (Quote from i.MX Yocto Project User's Guide.pdf page 6):

        Repo is a tool built on top of Git that makes it easier to manage projects that contain multiple repositories, which
        do not need to be on the same server. Repo complements very well the layered nature of the Yocto Project,
        making it easier for users to add their own layers to the BSP.

        To install the “repo” utility, perform these steps:
        1. Create a bin folder in the home directory.
            $ mkdir ~/bin (this step may not be needed if the bin folder already exists)
            $ curl https://storage.googleapis.com/git-repo-downloads/repo > ~/bin/repo
            $ chmod a+x ~/bin/repo
        2. Add the following line to the .bashrc file to ensure that the ~/bin folder is in your PATH variable.
            export PATH=~/bin:$PATH

Step 3:
    -First, make sure that Git is set up properly with the commands below (Quote from i.MX Yocto Project User's Guide.pdf page 6):
        $ git config --global user.name "Your Name"
        $ git config --global user.email "Your Email"
        $ git config --list
        The i.MX Yocto Project BSP Release directory contains a sources directory, which contains the recipes used
        to build one or more build directories, and a set of scripts used to set up the environment.
        The recipes used to build the project come from both the community and i.MX. The Yocto Project layers are
        downloaded to the sources directory. This sets up the recipes that are used to build the project.

Step 4:
    The following steps are just possible with repo installed!

    -Make a directory for yocto-release to be cloned:
        $ mkdir imx-yocto-bsp
        $ cd imx-yocto-bsp

    -First install the i.MX Linux BSP repo
        $ repo init -u git://github.com/nxp-imx/imx-manifest.git -b imx-linux-langdale -m imx-6.1.1-1.0.0.xml

    -Download the Yocto Project Layers:
        $ repo sync

    If errors on repo init, remove the .repo directory and try repo init again.


Step 5:
    -Follow the steps below to clone the #meta-fus' repository to '/imx-yocto-bsp/sources/':
        $ cd /imx-yocto-bsp/sources/
        $ git clone /mnt/git/linux/fsimx8ulp/meta-fus.git

    -After cloning the meta-fus.git to source follow this step:
        $ DISTRO=fs-imx8ulp-wayland MACHINE=fsimx8ulp source imx-setup-release.sh -b build

        This output comes after the command above:
            
            "Build directory is  build
            '/home/developer/Documents/bearbeitung/imx-yocto-bsp'

            Welcome to Freescale Community BSP

            The Yocto Project has extensive documentation about OE including a
            reference manual which can be found at:
            http://yoctoproject.org/documentation

            For more information about OpenEmbedded see their website:
              http://www.openembedded.org/

            You can now run 'bitbake <target>'

            Common targets are:
              core-image-minimal
              meta-toolchain
              meta-toolchain-sdk
              adt-installer
              meta-ide-support

            Your configuration files at build have not been touched.
            cp: overwrite './conf/local.conf'? y
            cp: overwrite './conf/bblayers.conf'? y
            BSPDIR=
            BUILD_DIR=.
            meta-fus directory found"

    The build directory is created. The working directory is now '/imx-yocto-bsp/build'

    In order to go further, do not close the terminal! 
        If you close it, apply the step above: '$ DISTRO=fs-...'.

    -To add the 'meta-fus' path to the 'bblayers.conf' file located in '/imx-yocto-bsp/build/conf', follow these steps:

        1. Open the 'bblayers.conf' file which is located in the '/imx-yocto-bsp/build/conf' directory.
        2. Navigate to the end of the file.
        3. Paste this line: BBLAYERS += "${BSPDIR}/sources/meta-fus"
        4. Save and close the file.
Step 6:
    -To build the linux-package use this command:
        $bitbake linux-fsimx8ulp

    -To build the image-package use this command:
        $bitbake imx-image-core

NOTE:

The MACHINE and DISTRO can also changed in local.conf under 'build/conf'

For SOLDERCORE8ULP with REV0.1 use please: 'MACHINE=rev_0_fsimx8ulp'
For SOLDERCORE8ULP with REV1.0 use please: 'MACHINE=fsimx8ulp'
These conf-files are under '/sources/meta-fus/conf/machine'

For DISTRO with x11 please use: 'DISTRO=fs-imx8ulp-xwayland'
For DISTRO without x11 please use: 'DISTRO=fs-imx8ulp-wayland'

