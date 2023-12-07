FROM quay.io/keycloak/keycloak:latest as builder

# Enable health and metrics support
ENV KC_HEALTH_ENABLED=true
ENV KC_METRICS_ENABLED=true

# Configure a database vendor
ENV KC_DB=postgres

WORKDIR /opt/keycloak
# for demonstration purposes only, please make sure to use proper certificates in production instead
RUN keytool -genkeypair -storepass password -storetype PKCS12 -keyalg RSA -keysize 2048 -dname "CN=server" -alias server -ext "SAN:c=DNS:localhost,IP:127.0.0.1" -keystore conf/server.keystore
# hotrod for remote ispn
COPY cache-ispn-jdbc-ping.xml /opt/keycloak/conf/cache-ispn-jdbc-ping.xml
ENV KC_CACHE_CONFIG_FILE=cache-ispn-jdbc-ping.xml


# RUN bin/kc.sh build --http-relative-path=/auth/ --cache-stack=tcp --health-enabled=true --metrics-enabled=true

FROM docker.io/ubiqube/ubi-almalinux9-java17:latest as base

# change these values to point to a running postgres instance
ENV KC_DB=postgres
ENV KC_DB_URL=jdbc:postgresql://db:5432/keycloak
ENV KC_DB_USERNAME=keycloak
ENV KC_DB_PASSWORD=keycloak

EXPOSE 8080
EXPOSE 8443


FROM base as builder2
COPY --from=builder /opt/keycloak/ /opt/keycloak/


WORKDIR /tmp

WORKDIR /opt/keycloak

RUN curl -L "http://nexus.ubiqube.com/service/rest/v1/search/assets/download?sort=version&repository=maven-public&maven.groupId=com.ubiqube.kc&maven.artifactId=keycloak-adapter&maven.extension=jar" --output providers/keycloak-adapter.jar
RUN curl -L "http://nexus.ubiqube.com/service/rest/v1/search/assets/download?sort=version&repository=maven-public&maven.groupId=com.ubiqube.kc&maven.artifactId=keycloak-theme&maven.extension=jar" --output providers/keycloak-theme.jar

RUN mkdir -p data/import
COPY main.json data/import/main.json

RUN bin/kc.sh build --http-relative-path=/auth/ --cache-stack=tcp --health-enabled=true --metrics-enabled=true

FROM base

COPY --from=builder2 /opt/keycloak/ /opt/keycloak/

WORKDIR /opt/keycloak


ENTRYPOINT ["/opt/keycloak/bin/kc.sh"]
CMD ["start", "--import-realm", "--optimized","--http-enabled=true", "--hostname-strict=false", "--hostname-strict-backchannel=true", "--proxy=edge", "--log-console-color=true"]

HEALTHCHECK --interval=1m --timeout=30s --retries=3 CMD timeout 10s bash -c '> /dev/tcp/127.0.0.1/8080'
