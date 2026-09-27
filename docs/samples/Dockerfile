# Highlighting sample only; do not build this file.
FROM scratch
ARG ITEM_COUNT=4
ENV NAME="Matrix"
LABEL description="Identity syntax sample"
WORKDIR /sample
COPY identity-syntax.json /sample/items.json
CMD ["/sample/example", "--count", "4"]
