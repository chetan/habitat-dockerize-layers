
An attempt to build lighter docker images using layers

## pkg-dockerize-cache

Modifies the original pkg-dockerize code only very slightly:

* Installs all package runtime dependecies when creating rootfs (studio)
* Adds a docker `RUN` command to install the final package
* Remove `--no-cache` from the docker build command to allow re-use

Even with caching, the base layer isn't always re-used (not sure, but I think
it's due to the way docker computes changes for `ADD` commands).

## pkg-dockerize-layer

This is a slightly larger modification which produces two docker images as the
final output.

* Base image which includes only runtime dependencies
* Named as `origin/pkg_deps_<hash>` where hash is a hash computed from the names of the runtime deps
* "Runtime" image which installs the final package and uses previous image as the base

This gives much better reuse of layers and totally avoids re-building the base at all.
