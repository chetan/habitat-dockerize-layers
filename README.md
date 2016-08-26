
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
* Named as `origin/pkg_deps:<hash>` where hash is computed from the names (idents) of the runtime deps
* "Runtime" image which installs the final package and uses previous image as the base

This gives much better reuse of layers and totally avoids re-building the base at all. Final images:

```
REPOSITORY                                  TAG                    IMAGE ID            CREATED             SIZE
chetan/foobar                               0.1.0-20160826204445   c3b2ed108437        5 seconds ago        177.8 MB
chetan/foobar                               latest                 c3b2ed108437        5 seconds ago        177.8 MB
chetan/habitat_export_base                  dadf80f42a2a2028       7921e8c8aac2        16 minutes ago       159.8 MB
chetan/foobar_base                          dadf80f42a2a2028       7921e8c8aac2        16 minutes ago       159.8 MB
```
