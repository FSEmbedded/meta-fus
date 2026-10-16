#! /usr/bin/env python3

# Copyright 2026 F&S Elektronik Systeme GmbH
#
# Permission is hereby granted, free of charge, to any person obtaining a copy of
# this software and associated documentation files (the “Software”), to deal in
# the Software without restriction, including without limitation the rights to use,
# copy, modify, merge, publish, distribute, sublicense, and/or sell copies of the
# Software, and to permit persons to whom the Software is furnished to do so,
# subject to the following conditions:
#
# The above copyright notice and this permission notice shall be included in all
# copies or substantial portions of the Software.
#
# THE SOFTWARE IS PROVIDED “AS IS”, WITHOUT WARRANTY OF ANY KIND, EXPRESS OR IMPLIED,
# INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
# FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT.
# IN NO EVENT SHALL THE AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM,
# DAMAGES OR OTHER LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE,
# ARISING FROM, OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS
# IN THE SOFTWARE.

import sys
import argparse
import json
import re
import subprocess
from pathlib import Path

scriptDir = Path(sys.argv[0]).parent.resolve()
dockerPathFile = scriptDir / ".docker_path"
supportedArchsFile = scriptDir / ".fusys_archs"

supportedDistros = ["fus-imx-wayland", "fus-imx-xwayland"]
supportedImages = ["fusys-image-core" , "fusys-image-eval", "fus-fw-bundle"]
supportedMachines = []

if supportedArchsFile.is_file():
    supportedMachines = supportedArchsFile.read_text(encoding="utf-8").splitlines()
supportedMachinesFile = scriptDir / ".fusys_machines"


deployPath = "tmp/deploy"
imagesPath = f"{deployPath}/images"
cylconeDXPath = f"cyclonedx-export"
sbomFile = "bom.json"
vexFile = "vex.json"
localConf = "conf/local.conf"

def setConfigValue(path, key, value):
    path = Path(path)
    line = f"{key} = \"{value}\"\n"
    lines = path.read_text(encoding="utf-8").splitlines(keepends=True) if path.exists() else []

    for index, existing_line in enumerate(lines):
        if existing_line.startswith(f"{key} ="):
            lines[index] = line
            break
    else:
        lines.append(line)
    print(f"Setting config value: {key} = \"{value}\"")
    path.write_text("".join(lines), encoding="utf-8")

class builds:
    def __init__(self, basedir=scriptDir):
        self.basedir = basedir
        self.buildList = {}
        self.availableBuilds()

    def getDistro(self, configFile):
        pattern = r"^\s*DISTRO\s*(?:\?\?=|\?=|=)\s*['\"]?([^'\"\s]+)"
        matches = re.findall(pattern, configFile.read_text(), re.MULTILINE)
        return matches[-1] if matches else None

    def getMachine(self, buildDir):
        #pattern = r"^\s*MACHINE\s*(?:\?\?=|\?=|=)\s*['\"]?([^'\"\s]+)"
        #matches = re.findall(pattern, configFile.read_text(), re.MULTILINE)
        path = buildDir / imagesPath
        matches = []
        if not path.is_dir():
            return {}
        for image in path.iterdir():
            if not image.is_dir():
                continue
            matches.append(image.name)

        return list(dict.fromkeys(matches))

    def getBuiltImages(self, buildDir, machine):
        path = buildDir /imagesPath / machine/ cylconeDXPath
        if not path.is_dir():
            return {}

        builtImages = {}
        for image in path.iterdir():
            if not image.is_dir():
                continue
            imagePath = buildDir /imagesPath / machine/ cylconeDXPath / image.name
            builtImages[image.name] = {
                "SBOM": str(imagePath / sbomFile) if (imagePath / sbomFile).is_file() else None,
                "VEX": str(imagePath / vexFile) if (imagePath / vexFile).is_file() else None,
            }
        return builtImages

    def availableBuilds(self):
        self.buildList = {}
        for buildDir in self.basedir.iterdir():
            configFile = buildDir / localConf
            if not buildDir.is_dir() or not configFile.is_file():
                continue
            machines = {}
            for machine in self.getMachine(buildDir):
                machines[machine] = {
                    "DEPLOY_PATH": str(self.basedir / buildDir / imagesPath / machine),
                    "BUILT_IMAGES": self.getBuiltImages(buildDir, machine),
                }

            self.buildList[buildDir.name] = {
                "CONFIG_FILE": str(self.basedir / configFile),
                "DISTRO": self.getDistro(configFile),
                "MACHINES": machines,
            }
        return self.buildList

class fsbuild:
    def __init__(self, scriptDir=scriptDir):
        self.scriptDir = scriptDir
        self.builds = builds(self.scriptDir)
        if dockerPathFile.is_file():
            self.docker_path = dockerPathFile.read_text().strip()
        else:
            self.docker_path = None

    def run_cmd(self, cmd):
        if self.docker_path:
            cmd = f"python3 {self.docker_path} \"{cmd}\""
        print(f"Running command: {cmd}")
        subprocess.run(f"{cmd}", shell=True, check=True, executable="/bin/bash")

    def getBuildsJSON(self):
        return json.dumps(self.builds.buildList)

    def printBuildsJSON(self):
        print(json.dumps(self.builds.buildList, indent=2))

    def supportedMachines(self):
        return list(supportedMachines)

    def supportedDistros(self):
        return list(supportedDistros)

    def supportedImages(self):
        return list(supportedImages)

    def availableBuilds(self):
        return list(self.builds.availableBuilds().keys())

    def getBuildedImages(self, build):
        buildData = self.builds.buildList.get(build, {})
        imageNames = []
        for machineData in buildData.get("MACHINES", {}).values():
            for imageName in machineData.get("BUILT_IMAGES", {}):
                if imageName not in imageNames:
                    imageNames.append(imageName)
        return imageNames

    def setupBuild(self, distro, machine=None, name=None):
        if not distro or not machine:
            raise ValueError("distro and machine must be specified")
        buildName = name or f"build-{machine}-{distro}"
        self.run_cmd(
            f"cd yocto-fus &&  DISTRO={distro} MACHINE={machine} . fus-setup-release.sh -b {buildName}"
        )
        return buildName

    def buildName(self, name=None):
        availableBuilds = self.builds.availableBuilds()
        buildName = name or next(iter(availableBuilds), None)
        if not buildName:
            raise ValueError("Please setup a build first")
        if buildName not in availableBuilds:
            raise ValueError(f"build {buildName} not found. Please setup build first")
        return buildName

    def getSbom(self, build, image):
        path = self.scriptDir / build / cylconeDXPath / image / sbomFile
        return str(path) if path.is_file() else None

    def getVex(self, build, image):
        path = self.scriptDir / build / cylconeDXPath / image / vexFile
        return str(path) if path.is_file() else None

    def getDeployPath(self, build, machine=None):
        buildName = self.buildName(build)
        buildData = self.builds.buildList.get(buildName, {})
        machineData = buildData.get("MACHINES", {}).get(machine, {})
        deployPath = machineData.get("DEPLOY_PATH")
        return deployPath

    def openShell(self, name=None):
        buildName = self.buildName(name)
        self.run_cmd(f"cd yocto-fus && . setup-environment {buildName} && bash ")

    def openLocalconf(self, name=None):
        buildName = self.buildName(name)
        subprocess.run(["open", str(self.builds.buildList.get(buildName, {}).get("CONFIG_FILE"))], check=True)

    def openDeploy(self, buildName=None, machine=None):
        deployPath = self.getDeployPath(buildName, machine)
        if deployPath is None:
            raise FileNotFoundError("Deploy directory not found")
        subprocess.run(["open", deployPath], check=True)

    def openSourceDir(self):
        sourceDir = self.scriptDir / "sources"
        if not sourceDir.is_dir():
            raise FileNotFoundError("Source directory not found")
        subprocess.run(["open", str(sourceDir)], check=True)

    def build(self, image, name=None, machine=None):
        buildName = self.buildName(name)
        if machine is not None and machine != "":
            setConfigValue(self.builds.buildList.get(buildName, {}).get("CONFIG_FILE"), "MACHINE", machine)
        self.run_cmd(
            f"cd yocto-fus && . setup-environment {buildName} && bitbake {image}"
        )

def parseNamedArguments(parser, option, arguments, requiredKeys):
    try:
        parsedArguments = dict(argument.split("=", 1) for argument in arguments)
    except ValueError:
        parsedArguments = {}
    if set(parsedArguments) != set(requiredKeys):
        requirements = " and ".join(f"{key}=..." for key in requiredKeys)
        parser.error(f"{option} requires {requirements}")
    return parsedArguments

if __name__ == "__main__":

    build = fsbuild()

    parser = argparse.ArgumentParser(description="F&S Yocto Build Environment")

    parser.add_argument("--supportedDistros", help="List available distros", action="store_true")
    parser.add_argument("--supportedMachines", help="List available machines", action="store_true")
    parser.add_argument("--supportedImages", help="List available images", action="store_true")
    parser.add_argument("--availableBuilds", help="List available builds", action="store_true")
    parser.add_argument("--setupBuild", "--setup-build", dest="setupBuild", nargs=3,
                        metavar=("distro=...", "machine=...", "build=..."),
                        help="Setup build, for example distro=fus-imx-wayland machine=fsimx8mp build=test")
    parser.add_argument("--build", nargs=3, metavar=("image=...", "build=...", "machine=..."),
                        help="Build an image, for example image=fusys-image-core build=test machine=fsimx8mp")
    parser.add_argument("--openShell", nargs=1, metavar="build=...",
                        help="Open build in console, for example build=test")
    parser.add_argument("--openLocalconf", nargs=1, metavar="build=...",
                        help="Open local.conf, for example build=test")
    parser.add_argument("--openDeploy", nargs=2, metavar=("machine=...", "build=..."),
                         help="Open deploy directory, for example machine=fsimx8mp build=test")
    parser.add_argument("--getBuildedImages", nargs=1, metavar="build=...",
                        help="Get built images, for example build=test")
    parser.add_argument("--printBuildsJSON", help="Print builds in JSON format", action="store_true")
    parser.add_argument("--openSourceDir", help="Open the yocto source directory", action="store_true")

    args = parser.parse_args()

    if args.supportedDistros:
        for distro in build.supportedDistros():
            print(distro)
    elif args.supportedImages:
        for image in build.supportedImages():
            print(image)
    elif args.supportedMachines:
        for machine in build.supportedMachines():
            print(machine)
    elif args.availableBuilds:
        for buildName in build.availableBuilds():
            print(buildName)
    elif args.getBuildedImages:
        args = parseNamedArguments(parser, "--getBuildedImages", args.getBuildedImages, ("build",))
        images = build.getBuildedImages(args["build"])
        print("\n".join(images) if images else "None found")
    elif args.setupBuild:
        args = parseNamedArguments(parser, "--setupBuild", args.setupBuild,
                                   ("distro", "machine", "build"))
        try:
            build.setupBuild(args["distro"], args["machine"], args["build"])
        except ValueError as error:
            parser.error(str(error))
    elif args.openShell:
        args = parseNamedArguments(parser, "--openShell", args.openShell, ("build",))
        build.openShell(args["build"])
    elif args.openLocalconf:
        args = parseNamedArguments(parser, "--openLocalconf", args.openLocalconf, ("build",))
        build.openLocalconf(args["build"])
    elif args.openDeploy:
        args = parseNamedArguments(parser, "--openDeploy", args.openDeploy, ("machine", "build"))
        build.openDeploy(args["build"], args["machine"])
    elif args.openSourceDir:
        build.openSourceDir()
    elif args.build:
        args = parseNamedArguments(parser, "--build", args.build, ("image", "build", "machine"))
        build.build(args["image"], args["build"], args["machine"])
    elif args.printBuildsJSON:
        build.printBuildsJSON()

