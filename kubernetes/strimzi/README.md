# Strimzi Installation Instructions
#
# NOTE: terraform/addons.tf now installs the Strimzi operator automatically
# (helm_release.strimzi_primary / helm_release.strimzi_dr). This file is kept
# as a manual fallback if you disable that automation.
#
# The Strimzi operator provides Kubernetes CRDs for managing Kafka clusters.
# 
# Installation:
#   kubectl apply -f 00-namespace.yaml
#   kubectl create -f 'https://strimzi.io/install/latest?namespace=kafka'
#
# Verify:
#   kubectl get pods -n kafka
#   kubectl get crd | grep kafka
#
# Expected CRDs:
#   - kafkas.kafka.strimzi.io
#   - kafkatopics.kafka.strimzi.io  
#   - kafkausers.kafka.strimzi.io
#   - kafkaconnects.kafka.strimzi.io
#   - kafkamirrormaker2s.kafka.strimzi.io
#
# Documentation: https://strimzi.io/docs/operators/latest/overview.html
