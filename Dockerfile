FROM fedora:22

RUN dnf update -y \
  && dnf install -y \
    findutils \
    git \
    java-1.8.0-openjdk-headless \
    java-1.8.0-openjdk-devel \
    kubernetes-client \
    wget \
    zip \
  && rm -rf /var/cache/dnf/* /var/log/dnf*.log

ENV JENKINS_HOME /var/jenkins_home
ENV JENKINS_SLAVE_AGENT_PORT 50000

# Jenkins is ran with user `jenkins`, uid = 1000
# If you bind mount a volume from host/volume from a data container, 
# ensure you use same uid
RUN useradd -d "$JENKINS_HOME" -u 1000 -m -s /bin/bash jenkins

# Jenkins home directoy is a volume, so configuration and build history 
# can be persisted and survive image upgrades
VOLUME /var/jenkins_home

# `/usr/share/jenkins/ref/` contains all reference configuration we want 
# to set on a fresh new installation. Use it to bundle additional plugins 
# or config file with your custom jenkins Docker image.
RUN mkdir -p /usr/share/jenkins/ref/{init.groovy.d,plugins}

ENV TINI_SHA 066ad710107dc7ee05d3aa6e4974f01dc98f3888

# Use tini as subreaper in Docker container to adopt zombie processes 
RUN curl -fL https://github.com/krallin/tini/releases/download/v0.5.0/tini-static -o /bin/tini && chmod +x /bin/tini \
  && echo "$TINI_SHA /bin/tini" | sha1sum -c -

COPY init.groovy /usr/share/jenkins/ref/init.groovy.d/tcp-slave-agent-port.groovy

# Pre-install Jenkins Kubernetes plugin (and dependencies)
ENV JENKINS_CREDENTIALS_VERSION 1.24
ENV JENKINS_CREDENTIALS_SHA 9400dcaa054f2a332628073f5333842280be4fe8

RUN curl -fL https://updates.jenkins-ci.org/download/plugins/credentials/$JENKINS_CREDENTIALS_VERSION/credentials.hpi \
  -o /usr/share/jenkins/ref/plugins/credentials.hpi \
  && echo "$JENKINS_CREDENTIALS_SHA /usr/share/jenkins/ref/plugins/credentials.hpi" | sha1sum -c -

# As the credentials plugin is also bundled with jenkins, avoid overwriting it on startup
RUN touch /usr/share/jenkins/ref/plugins/credentials.jpi.pinned

ENV JENKINS_DURABLETASK_VERSION 1.6
ENV JENKINS_DURABLETASK_SHA c60d220cd5a6bdd3deaaccae9f58f16d1f2c0259

RUN curl -fL https://updates.jenkins-ci.org/download/plugins/durable-task/$JENKINS_DURABLETASK_VERSION/durable-task.hpi \
  -o /usr/share/jenkins/ref/plugins/durable-task.hpi \
  && echo "$JENKINS_DURABLETASK_SHA /usr/share/jenkins/ref/plugins/durable-task.hpi" | sha1sum -c -

ENV JENKINS_KUBERNETES_VERSION 0.4.1
ENV JENKINS_KUBERNETES_SHA ae5016d9dce5afbcee22f00d0787016c430fba48

RUN curl -fL https://updates.jenkins-ci.org/download/plugins/kubernetes/$JENKINS_KUBERNETES_VERSION/kubernetes.hpi \
  -o /usr/share/jenkins/ref/plugins/kubernetes.hpi \
  && echo "$JENKINS_KUBERNETES_SHA /usr/share/jenkins/ref/plugins/kubernetes.hpi" | sha1sum -c -

ENV JENKINS_VERSION 1.625.1
ENV JENKINS_SHA c96d44d4914a154c562f21cd20abdd675ac7f5f3

# could use ADD but this one does not check Last-Modified header 
# see https://github.com/docker/docker/issues/8331
RUN curl -fL http://mirrors.jenkins-ci.org/war-stable/$JENKINS_VERSION/jenkins.war -o /usr/share/jenkins/jenkins.war \
  && echo "$JENKINS_SHA /usr/share/jenkins/jenkins.war" | sha1sum -c -

ENV JENKINS_UC https://updates.jenkins-ci.org
RUN chown -R jenkins "$JENKINS_HOME" /usr/share/jenkins/ref

# for main web interface:
EXPOSE 8080

# will be used by attached slave agents:
EXPOSE 50000

ENV COPY_REFERENCE_FILE_LOG $JENKINS_HOME/copy_reference_file.log

USER jenkins

COPY jenkins.sh /usr/local/bin/jenkins.sh
ENTRYPOINT ["/bin/tini", "--", "/usr/local/bin/jenkins.sh"]

# from a derived Dockerfile, can use `RUN plugin.sh active.txt` to setup /usr/share/jenkins/ref/plugins from a support bundle
COPY plugins.sh /usr/local/bin/plugins.sh
