{lib, ...}: {
  imports = [ ./worker-N.nix ];

  # Mayastor needs hugetlbfs-backed 2 MiB pages and a few host kernel modules.
  # Keep this on its own netboot profile so ordinary KubeNodeSmith workers do
  # not permanently reserve RAM for huge pages.
  boot.kernelParams = [
    "cgroup_enable=cpuset"
    "cgroup_memory=1"
    "cgroup_enable=memory"
    "hugepagesz=2M"
    "hugepages=1024"
  ];
  boot.kernelModules = [ "nbd" "xfs" "nvme_core" "nvme_fabrics" "nvme_tcp" "nvme_rdma" "nvme_loop" ];

  users.groups.hugepages.gid = 6969;
  systemd.tmpfiles.rules = [
    "d /dev/hugepages 0775 root hugepages -"
  ];
  systemd.mounts = [
    {
      what = "hugetlbfs";
      where = "/dev/hugepages";
      type = "hugetlbfs";
      options = "pagesize=2M,gid=6969,mode=0775";
      wantedBy = [ "basic.target" ];
      requiredBy = [ "basic.target" ];
    }
  ];

  # 48 GiB VM - 2 GiB huge pages - 5 GiB system reserve leaves 41 GiB
  # allocatable. The Coder pod requests 40 GiB, leaving 1 GiB for DaemonSets.
  services.k3s.extraFlags = lib.mkAfter [
    "--kubelet-arg=system-reserved=memory=5Gi"
  ];
}
