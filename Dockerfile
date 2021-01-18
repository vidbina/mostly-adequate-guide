# NOTE: Do not provide a default value in order to make this choice explicit
ARG IMAGE


FROM ${IMAGE} AS build

# Install system dependencies
ARG SYSTEM_PACKAGES=""
RUN apt-get update && apt-get install -y --no-install-recommends \
    ${SYSTEM_PACKAGES} \
    && rm -rf /var/lib/apt/lists/*

ARG PROJECT=app
ENV PROJECT=${PROJECT}

WORKDIR /tmp/${PROJECT}

# Copy Node.js dependency manifest into temporary working directory
COPY package.json /tmp/${PROJECT}/

# Install Node.js packages
ARG PACKAGE_INSTALLER="npm install"
RUN ${PACKAGE_INSTALLER}


FROM ${IMAGE} AS production

# Set the default user to the built-in node (non-root) user
USER node

# Copy libraries from build image
COPY --from=build /usr/lib /usr/lib

ARG PROJECT=app
ENV PROJECT=${PROJECT}

# For the production image, application-specific assets are stored into a
# subdirectory of "/opt" which is the FHS-designated destination for add-on
# application software packages.
WORKDIR /opt/${PROJECT}

# Copying folders from the root directory into an image may result to files
# ending up in that image that were not intended for production. We propose
# updating your .dockerignore file to first ignore all files and then gradually
# provide exception rules for for every file or folder that you wish to
# include. This approach makes it more explicit what ends up finding its way
# into an image and may prove helpful in minimizing the chances of assets
# creeping into your image unintentionally.
# https://docs.docker.com/engine/reference/builder/#dockerignore-file

COPY --chown=node . /opt/${PROJECT}/

# Run installation command
# TODO: Experiment with copying node packages from build image
COPY --chown=node --from=build /tmp/${PROJECT}/node_modules /opt/${PROJECT}/node_modules

# NOTE: Do not define default to PORTS in order to make this choice explicit
ARG PORTS
EXPOSE ${PORTS}
