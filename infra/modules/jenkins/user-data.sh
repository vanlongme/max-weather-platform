#!/bin/bash
set -euo pipefail
exec > /var/log/user-data.log 2>&1

apt-get update -y
apt-get install -y openjdk-17-jre git curl unzip docker.io

systemctl enable --now docker
usermod -aG docker ubuntu

curl -sf https://awscli.amazonaws.com/awscli-exe-linux-x86_64.zip -o /tmp/awscli.zip
unzip -q /tmp/awscli.zip -d /tmp
/tmp/aws/install
rm -rf /tmp/aws /tmp/awscli.zip

curl -sLO https://dl.k8s.io/release/v1.30.6/bin/linux/amd64/kubectl
install -m 0755 kubectl /usr/local/bin/kubectl
rm kubectl

curl -sf https://raw.githubusercontent.com/helm/helm/main/scripts/get-helm-3 | bash

curl -fsSL https://pkg.jenkins.io/debian-stable/jenkins.io-2023.key | tee /usr/share/keyrings/jenkins-keyring.asc > /dev/null
echo "deb [signed-by=/usr/share/keyrings/jenkins-keyring.asc] https://pkg.jenkins.io/debian-stable binary/" | tee /etc/apt/sources.list.d/jenkins.list > /dev/null
apt-get update -y
apt-get install -y jenkins
usermod -aG docker jenkins
systemctl enable --now jenkins

sleep 30
cp /var/lib/jenkins/secrets/initialAdminPassword /home/ubuntu/initialAdminPassword 2>/dev/null || true
chown ubuntu:ubuntu /home/ubuntu/initialAdminPassword 2>/dev/null || true
