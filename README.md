Description
===========
Install and configure Etcd cluster on Centos with Docker and Fleet.

Version 1.0-43p
-------------

[![Install](https://raw.github.com/qubell-bazaar/component-skeleton/master/img/install.png)](https://express.qubell.com/applications/upload?metadataUrl=https://raw.github.com/qubell-bazaar/component-docker-networking/1.0-43p/meta.yml)

Configurations
--------------
 - Centos 7.1
 - Etcd 2.1
 - Docker 1.9
 - Fleet 0.11.5

Pre-requisites
--------------
 - Configured Cloud Account a in chosen environment
 - Internet access from target compute

Implementation notes
 --------------------
 - Installation based on execruns.
 - Etcd configuration based on [Etcd Clustering in AWS](http://engineering.monsanto.com/2015/06/12/etcd-clustering/).
      Tonomi Platfom compute pool used as a source instead AWS autoscaling groups.
      After getting resources lists from Tonomi Platform, script looking for first alive etcd member, retrieves cluster membership information from it. Further actions are based on current node membership:
         * do nothing if node is already a member of an active cluster
         * join to existing cluster if current node not a member of an active cluster
         * form a new cluster if no active cluster has been discovered
 - One-by-one strategy is used for scaling process ("batchSize: 1" parameter for Etcd installation execrun step) according to [Etcd Runtime Reconfiguration](https://github.com/coreos/etcd/blob/master/Documentation/runtime-configurat    ion.md).
 - Fleet and Docker etcd entries dynamically updated during scaling process.

