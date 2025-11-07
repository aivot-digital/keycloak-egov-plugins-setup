FROM python:3.13.7-alpine3.22 AS builder

RUN mkdir /app

WORKDIR /app

COPY ./requirements.txt /app/requirements.txt
RUN pip install -r /app/requirements.txt

COPY ./data /app/data
COPY ./templates /app/templates
COPY ./build.py /app/build.py

RUN python build.py

FROM adorsys/keycloak-config-cli:6.4.0-26.1.0

# Set build version and date
ARG BUILD_VERSION=0.0.0
ARG BUILD_NUMBER=0
ARG BUILD_DATE=2025-05-24T10:15:00Z

# Set app metadata
LABEL org.opencontainers.image.created=$BUILD_DATE
LABEL org.opencontainers.image.url="https://github.com/aivot-digital/keycloak-egov-plugins-setup"
LABEL org.opencontainers.image.documentation="https://wiki.teamaivot.de/de/dokumentation/gover"
LABEL org.opencontainers.image.source="https://github.com/aivot-digital/keycloak-egov-plugins-setup"
LABEL org.opencontainers.image.version=$BUILD_VERSION
LABEL org.opencontainers.image.revision=$BUILD_NUMBER
LABEL org.opencontainers.image.vendor="Aivot"
LABEL org.opencontainers.image.title="Keycloak eGov Plugins Setup"
LABEL org.opencontainers.image.description="Configuration of Keycloak with eGov plugins"

# Configure Keycloak Config CLI to use environment variable substitution
ENV IMPORT_VARSUBSTITUTION_ENABLED=true

# Copy the generated configuration files from the builder stage
COPY --from=builder /app/.generated /configs

# Copy master realm specific configuration files
COPY ./master/bootstrap-master.yml /configs/bootstrap-master.yml
COPY ./master/master.yml /configs/master.yml

# Copy entrypoint script
COPY ./entrypoint.sh /opt/keycloak-config-cli/entrypoint.sh

# Switch to root user to set permissions
USER 0

# Make entrypoint executable
RUN chmod +x /opt/keycloak-config-cli/entrypoint.sh

# Create and own password blacklists directory
RUN mkdir "/password-blacklists/" && \
    chown -R 65534:65534 /password-blacklists/ && \
    chmod 755 /password-blacklists/

# Switch back to non-root user
USER nobody

# Set the entrypoint to the custom script
ENTRYPOINT ["/opt/keycloak-config-cli/entrypoint.sh"]
