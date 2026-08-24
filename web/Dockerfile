# The Godot web export, served by nginx. The export itself is built by
# .github/workflows/build.yml and downloaded into ./site as the build context —
# nothing here compiles the game, so this image is a copy and two headers.
#
# 1.31-alpine, not :alpine: the pin is what makes the .wasm MIME claim durable.
# nginx ships `application/wasm wasm;` in conf/mime.types since 1.21.1 (verified
# present at this tag), so a Godot export needs no MIME configuration at all.
FROM nginx:1.31-alpine

COPY site/ /usr/share/nginx/html/
COPY coop-coep.conf /etc/nginx/conf.d/default.conf
